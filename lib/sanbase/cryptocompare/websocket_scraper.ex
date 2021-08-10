defmodule Sanbase.Cryptocompare.WebsocketScraper do
  defmodule HealthcheckError do
    defexception [:message]
  end

  @moduledoc ~s"""
  Scrape the prices from Cryptocompare websocket API
  https://min-api.cryptocompare.com/documentation/websockets

  Use the cryptocompare API to fetch prices aggregated across many exchanges
  in near-realtime. For every base/quote asset pairs fetch:
    - price
    - volume 24h (sliding window) - in number of tokens and in the quote asset currency
    - top tier exchanges volume 24h (sliding window) - in number of tokens and
      in the quote asset currency
  """
  use WebSockex

  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint, as: AssetPricesPoint
  alias Sanbase.Cryptocompare.PricePoint, as: CryptocompareAssetPricesPoint
  alias Sanbase.Cryptocompare.PriceOnlyPoint, as: CryptocompareAssetPricesOnlyPoint

  require Logger
  require Sanbase.Utils.Config, as: Config

  # giving it a name makes sure only one instance of the scraper is alive at a time
  @name :cryptocompare_websocket_scraper

  @asset_price_pairs_exporter :asset_price_pairs_exporter
  @asset_price_pairs_only_exporter :asset_price_pairs_only_exporter
  @asset_prices_exporter :prices_exporter

  # Attempt a healthcheck every `@healthcheck_interval milliseconds` and check
  # whether the last price message was received within the last `@price_message_timeout`
  # milliseconds. If this check fails `@healthcheck_max_failures` times, terminate
  # the exporter as there might be something wrong with the connection. The parameters
  # are picked to be bigger so the number of resets is not too high and we don't
  # reach the allowed number of websocket connections attempts.
  @healthcheck_interval 60_000
  @healthcheck_tolerance 60_000
  @healthcheck_max_failures 5

  def child_spec(_opts \\ []) do
    %{
      id: :__cryptocompare_websocket_price_scraper__,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start_link() do
    state = %{
      start_time: DateTime.utc_now(),
      last_points: %{},
      healthcheck_sequential_failures: 0,
      subscriptions: MapSet.new(),
      msg_number: 0,
      last_price_message_time: DateTime.utc_now()
    }

    extra_headers = [{"authorization", "Apikey #{api_key()}"}]

    Process.send_after(@name, :healthcheck, @healthcheck_interval)

    WebSockex.start_link(websocket_url(), __MODULE__, state,
      name: @name,
      extra_headers: extra_headers
    )
  end

  def enabled?(), do: Config.get(:enabled?) |> String.to_existing_atom()

  def terminate(reason, state) do
    base_error_msg = "[CryptocompareWS] Terminate the websocket connection #{state[:socket_id]}."

    error_msg =
      case reason do
        {%{} = exception, _stacktrace} ->
          base_error_msg <> " Reason: #{Exception.message(exception)}"

        _ ->
          base_error_msg <> " Reason: #{inspect(reason)}"
      end

    Logger.error(error_msg)

    :ok
  end

  def handle_info(:healthcheck, state) do
    # If more than 3 consecutive times there are no new messages in the last
    # 30 seconds, we consider the connection to be dead and it will be terminated
    # so it can be freshly started.
    last_message_elapsed =
      DateTime.diff(DateTime.utc_now(), state.last_price_message_time, :millisecond)

    state =
      case last_message_elapsed > @healthcheck_tolerance do
        true -> Map.update(state, :healthcheck_sequential_failures, 1, &(&1 + 1))
        false -> Map.put(state, :healthcheck_sequential_failures, 0)
      end

    if state.healthcheck_sequential_failures > @healthcheck_max_failures do
      raise(HealthcheckError,
        message: "More than #{@healthcheck_max_failures} consecutive healthchecks have failed"
      )
    end

    Process.send_after(self(), :healthcheck, @healthcheck_interval)

    {:ok, state}
  end

  def handle_info(:init_wildcard_subscription, state) do
    Logger.info("""
    [CryptocompareWS] Start the wildcard 5~CCCAGG~*~* subscription
    """)

    sub = %{action: "SubAdd", subs: ["5~CCCAGG~*~*"]}
    frame = {:text, Jason.encode!(sub)}
    {:reply, frame, state}
  end

  def handle_info(msg, state) do
    Logger.warn("[CryptocompareWS] Unhandled message received: #{inspect(msg)}")
    {:ok, state}
  end

  def handle_frame({_type, json_msg} = frame, state) when is_binary(json_msg) do
    # Decode the JSON so it can be pattern matches in the function header
    decoded_json = Jason.decode!(json_msg)
    handle_frame(decoded_json, frame, state)
  end

  def handle_frame(%{"MESSAGE" => "STREAMERWELCOME"} = msg, _frame, state) do
    Logger.info("[CryptocompareWS] Successfully connected websocket #{msg["SOCKET_ID"]}")
    state = Map.put(state, :socket_id, msg["SOCKET_ID"])

    # Subscribe if the subscriptions list is empty.
    if Enum.empty?(state.subscriptions), do: send(self(), :init_wildcard_subscription)

    {:ok, state}
  end

  def handle_frame(%{"MESSAGE" => "HEARTBEAT"}, _frame, state) do
    Logger.info("[CryptocompareWS] Received heartbeat on websocket #{state[:socket_id]}")
    {:ok, state}
  end

  def handle_frame(%{"MESSAGE" => "LOADCOMPLETE"}, _frame, state), do: {:ok, state}

  # Aggregate Index (CCCAGG)
  def handle_frame(%{"TYPE" => "5"} = msg, _frame, state) do
    now = DateTime.utc_now()
    point_unique_key = {"CCCAGG", msg["FROMSYMBOL"], msg["TOSYMBOL"]}

    last_point = Map.get(state.last_points, point_unique_key, %{})
    # The websocket messages received contain only the changed values compared to
    # the previous message. Store the last point, uniquely identified by the
    # 3 fields used in the unique key defined aboe fields, and use it to fill the
    # missing fields in subsequent frames.
    point =
      point_from_aggregated_index_message(msg)
      |> Enum.reduce(last_point, fn
        # In case the value is `nil`, put it only if the key is not present at all
        # This can happen with the first data point or if the pair does not have
        # support for some of the fields
        {key, nil}, acc -> Map.put_new(acc, key, nil)
        {key, value}, acc -> Map.put(acc, key, value)
      end)

    last_points = Map.put(state.last_points, point_unique_key, point)
    export_data_point(point, last_points)

    {:ok,
     %{
       state
       | last_points: last_points,
         msg_number: state.msg_number + 1,
         last_price_message_time: now
     }}
  end

  def handle_frame(%{"MESSAGE" => "FORCE_DISCONNECT"} = msg, _frame, state) do
    Logger.warn("""
    [CryptocompareWS] Received FORCE_DISCONNET for socket #{state.socket_id}. Reason: #{msg["INFO"]}
    """)

    # The reconnect is done in the handle_disconnect function
    {:ok, state}
  end

  def handle_frame(%{"MESSAGE" => "SUBSCRIBECOMPLETE"} = msg, _frame, state) do
    subscriptions = MapSet.put(state.subscriptions, msg["SUB"])
    {:ok, %{state | subscriptions: subscriptions}}
  end

  # For some reason from time to time there are empty frames
  def handle_frame(map, _frame, state) when map_size(map) == 0, do: {:ok, state}

  def handle_frame(_msg, frame, state) do
    Logger.info("[CryptocompareWS] Unhandled frame: #{inspect(frame)}")
    {:ok, state}
  end

  def handle_disconnect(_connetion_status_map, state) do
    Logger.info("[CryptocompareWS] Handle disconnect")

    # Cryptocompare websockets documentation states that after a disconnect,
    # the reconnect attempt must not happen sooner than 5 seconds after that
    # This disconnect handles all the cases of websocket disconnection.
    Process.sleep(5000)
    state = Map.put(state, :subscriptions, MapSet.new())
    {:reconnect, state}
  end

  def handle_cast({:send, {_type, _msg} = frame}, state) do
    {:reply, frame, state}
  end

  defp point_from_aggregated_index_message(msg) do
    %{
      source: "cryptocompare",
      datetime: msg["LASTUPDATE"] && DateTime.from_unix!(msg["LASTUPDATE"]),
      base_asset: msg["FROMSYMBOL"],
      quote_asset: msg["TOSYMBOL"],
      price: msg["PRICE"],
      volume_24h: msg["VOLUME24HOUR"],
      volume_24h_to: msg["VOLUME24HOURTO"],
      top_tier_volume_24h: msg["TOPTIERVOLUME24HOUR"],
      top_tier_volume_24h_to: msg["TOPTIERVOLUME24HOURTO"],
      volume_day: msg["VOLUMEDAY"],
      volume_day_to: msg["VOLUMEDAYTO"],
      volume_hour: msg["VOLUMEHOUR"],
      volume_hour_to: msg["VOLUMEHOURTO"]
    }
  end

  defp export_data_point(point, last_points) do
    export_asset_prices_topic(point, last_points)
    export_asset_price_pairs_topic(point)
    export_asset_price_pairs_only_topic(point)
  rescue
    e ->
      Logger.error("[CryptocompareWS] Failed to export data point: #{Exception.message(e)}")
  end

  defp export_asset_prices_topic(%{quote_asset: quote_asset} = point, last_points)
       when quote_asset in ["BTC", "USD"] do
    case Map.get(slug_data_map(), point.base_asset) do
      nil ->
        :ok

      slug ->
        # This works because before calling the export function, the point is
        # added to the last_points map. This implementation avoids any conditionals
        # that could be used to determine the current quote asset and fetch only
        # the other one. This is needed because one point contains data either
        # for USD or for BTC, but we need to combine both of them here.
        usd_point = Map.get(last_points, {"CCCAGG", point.base_asset, "USD"}, %{})
        btc_point = Map.get(last_points, {"CCCAGG", point.base_asset, "BTC"}, %{})

        tuple =
          %AssetPricesPoint{
            slug: slug,
            datetime: point.datetime,
            price_usd: usd_point[:price],
            price_btc: if(point.base_asset == "BTC", do: 1.0, else: btc_point[:price]),
            volume_usd: usd_point[:volume_24h_to] |> Sanbase.Math.to_integer(),
            marketcap_usd: nil
          }
          |> AssetPricesPoint.json_kv_tuple(slug, point.source)

        :ok = Sanbase.KafkaExporter.persist_async(tuple, @asset_prices_exporter)
    end
  end

  defp export_asset_prices_topic(_point, _last_points), do: :ok

  defp export_asset_price_pairs_topic(point) do
    tuple =
      point
      |> CryptocompareAssetPricesPoint.new()
      |> CryptocompareAssetPricesPoint.json_kv_tuple()

    :ok = Sanbase.KafkaExporter.persist_async(tuple, @asset_price_pairs_exporter)
  end

  defp export_asset_price_pairs_only_topic(point) do
    tuple =
      point
      |> CryptocompareAssetPricesOnlyPoint.new()
      |> CryptocompareAssetPricesOnlyPoint.json_kv_tuple()

    :ok = Sanbase.KafkaExporter.persist_async(tuple, @asset_price_pairs_only_exporter)
  end

  defp slug_data_map() do
    cache_key = {__MODULE__, :slug_data_map} |> Sanbase.Cache.hash()
    {:ok, map} = Sanbase.Cache.get_or_store({cache_key, 1800}, &get_slug_data_map/0)
    map
  end

  defp get_slug_data_map() do
    result =
      Sanbase.Model.Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
      |> Map.new()

    {:ok, result}
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)
  defp websocket_url(), do: "wss://streamer.cryptocompare.com/v2"
end
