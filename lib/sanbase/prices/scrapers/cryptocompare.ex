defmodule Sanbase.Price.Scraper.Cryptocompare.Websocket do
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

  require Logger
  require Sanbase.Utils.Config, as: Config

  # giving it a name makes sure only one instance of the scraper is alive at a time
  @name :cryptocompare_websocket_scraper

  def child_spec(_opts \\ []) do
    %{
      id: :__cryptocompare_websocket_price_scraper__,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start_link() do
    state = %{
      last_points: %{},
      subscriptions: MapSet.new(),
      msg_number: 0
    }

    WebSockex.start_link(websocket_url(), __MODULE__, state, name: @name)
  end

  def enabled?() do
    Config.get(:enabled?) |> String.to_existing_atom()
  end

  def terminate(_, _), do: :ok

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

  def handle_frame(%{"MESSAGE" => "HEARTBEAT"}, _frame, state), do: {:ok, state}
  def handle_frame(%{"MESSAGE" => "LOADCOMPLETE"}, _frame, state), do: {:ok, state}

  # Aggregate Index (CCCAGG)
  def handle_frame(%{"TYPE" => "5"} = msg, _frame, state) do
    point_unique_key = {msg["MARKET"], msg["FROMSYMBOL"], msg["TOSYMBOL"]}

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

    export_data_point(point)

    last_points = Map.put(state.last_points, point_unique_key, point)
    {:ok, %{state | last_points: last_points, msg_number: state.msg_number + 1}}
  end

  def handle_frame(%{"MESSAGE" => "FORCE_DISCONNECT"} = msg, _frame, state) do
    Logger.warn("""
    [CryptocompareWS] Received FORCE_DISCONNET for socket #{state.socket_id}. Reason: #{
      msg["INFO"]
    }
    """)

    # The reconnect is done in the handle_disconnect function
    {:ok, state}
  end

  def handle_frame(%{"MESSAGE" => "SUBSCRIBECOMPLETE"} = msg, _frame, state) do
    {:ok,
     %{
       state
       | subscriptions: MapSet.put(state.subscriptions, msg["SUB"])
     }}
  end

  # For some reason from time to time there are empty frames
  def handle_frame(map, _frame, state) when map_size(map) == 0, do: {:ok, state}

  def handle_frame(_msg, frame, state) do
    Logger.info("[CryptocompareWS] Unhandled frame: #{inspect(frame)}")

    {:ok, state}
  end

  def handle_disconnect(_connetion_status_map, state) do
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
      top_tier_volume_24h_to: msg["TOPTIERVOLUME24HOURTO"]
    }
  end

  @cryptocompare_prices_topic_exporter :cryptocompare_prices_exporter

  defp export_data_point(point) do
    tuple =
      point
      |> Sanbase.Price.Point.new()
      |> Sanbase.Price.Point.json_kv_tuple()

    :ok = Sanbase.KafkaExporter.persist_async(tuple, @cryptocompare_prices_topic_exporter)
  end

  defp apikey(), do: Config.get(:api_key)
  defp websocket_url(), do: "wss://streamer.cryptocompare.com/v2?api_key=#{apikey()}"
end
