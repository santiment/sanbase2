defmodule Sanbase.Cryptocompare.Price.WebsocketScraper do
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
  alias Sanbase.Cryptocompare.PriceOnlyPoint, as: CryptocompareAssetPricesOnlyPoint

  require Logger
  alias Sanbase.Utils.Config

  # giving it a name makes sure only one instance of the scraper is alive at a time
  @name :cryptocompare_websocket_scraper

  @asset_price_pairs_only_exporter :asset_price_pairs_only_exporter
  @asset_prices_exporter :prices_exporter

  # Every `@healthcheck_interval` ms, check the last price message arrived within
  # `@price_message_timeout` ms. `@healthcheck_max_failures` failures terminate the
  # exporter - the connection is likely broken. Kept large so resets stay rare and the
  # allowed number of websocket connection attempts is not hit.
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

  def enabled?(), do: Config.module_get(__MODULE__, :enabled?) |> String.to_existing_atom()

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
    # No new messages for 30 seconds, 3 times running: the connection is dead and is
    # terminated so it can start fresh.
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
    Logger.warning("[CryptocompareWS] Unhandled message received: #{inspect(msg)}")
    {:ok, state}
  end

  def handle_frame({_type, json_msg} = frame, state) when is_binary(json_msg) do
    # Decoded so the function header can pattern match on it
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
    # A message carries only what changed, so the last point (identified by the 3 fields of
    # the unique key above) is stored and fills the missing fields of later frames.
    point =
      point_from_aggregated_index_message(msg)
      |> Enum.reduce(last_point, fn
        # A `nil` value is put only when the key is absent entirely - the first data point,
        # or a pair not supporting some of the fields.
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
    Logger.warning("""
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

    # Cryptocompare's docs require at least 5 seconds before reconnecting. This handles
    # every websocket disconnection case.
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

      [_ | _] = slugs ->
        # A point carries either USD or BTC data, but both are needed. The point is added
        # to last_points before this is called, so both are read from there without
        # branching on which quote asset arrived.
        usd_point = Map.get(last_points, {"CCCAGG", point.base_asset, "USD"}, %{})
        btc_point = Map.get(last_points, {"CCCAGG", point.base_asset, "BTC"}, %{})

        tuples =
          slugs
          |> Enum.map(fn slug ->
            %AssetPricesPoint{
              slug: slug,
              datetime: point.datetime,
              price_usd: usd_point[:price],
              price_btc: if(point.base_asset == "BTC", do: 1.0, else: btc_point[:price]),
              volume_usd: usd_point[:volume_24h_to] |> Sanbase.Math.to_integer(),
              marketcap_usd: nil
            }
            |> AssetPricesPoint.json_kv_tuple(slug, point.source)
          end)

        :ok = Sanbase.KafkaExporter.persist_async(tuples, @asset_prices_exporter)
    end
  end

  defp export_asset_prices_topic(_point, _last_points), do: :ok

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
      Sanbase.Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
      |> Enum.reduce(%{}, fn {cryptocompare_slug, san_slug}, acc ->
        Map.update(acc, cryptocompare_slug, [san_slug], &[san_slug | &1])
      end)

    {:ok, result}
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)
  defp websocket_url(), do: "wss://streamer.cryptocompare.com/v2"
end
