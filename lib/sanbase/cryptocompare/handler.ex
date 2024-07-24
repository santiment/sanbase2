defmodule Sanbase.Cryptocompare.Handler do
  alias Sanbase.Cryptocompare.HTTPHeaderUtils
  alias Sanbase.Cryptocompare.ExporterProgress
  alias Sanbase.Utils.Config, as: Config

  require Logger

  @type option :: :module | :timestamps_key | :process_function | :remove_known_timestamps

  @doc ~s"""
  Get data from the Cryptocompare API.
  The body of the successful result is processed by the process_json_response_function/1
  passed as the argument.

  The opts need to provide the following arguments:
  - market
  - instrument
  - timestamp
  - limit
  - queue -- the oban queue
  """
  @spec get_data(String.t(), (String.t() -> {:ok, map()}), Keyword.t()) ::
          {:error, HTTPoison.Error.t()}
          | {:error, :first_timestamp_reached}
          | {:error, :rate_limit}
          | {:ok, min_timestamp :: non_neg_integer(), data_list :: list()}
  def get_data(url, process_json_response_function, opts)
      when is_function(process_json_response_function, 1) do
    timestamps_key = "#{opts[:market]}_#{opts[:instrument]}"

    case execute_http_request(url, opts) do
      {:ok, %{status_code: 200} = http_response} ->
        handle_http_response(http_response,
          queue: opts[:queue],
          timestamps_key: timestamps_key,
          process_function: process_json_response_function,
          remove_known_timestamps: true
        )

      {:ok, %{status_code: 404}} ->
        # The error is No HOUR entries available on or before <timestamp>
        {:error, :first_timestamp_reached}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_markets_and_instruments() do
    cache_key = {__MODULE__, :get_markets_and_instruments}
    Sanbase.Cache.get_or_store({cache_key, 600}, &do_get_markets_and_instruments/0)

    do_get_markets_and_instruments()
  end

  # Private function

  defp handle_http_response(http_response, opts) do
    queue = Keyword.fetch!(opts, :queue)
    timestamps_key = Keyword.fetch!(opts, :timestamps_key)
    process_function = Keyword.fetch!(opts, :process_function)

    case HTTPHeaderUtils.rate_limited?(http_response) do
      false ->
        timestamps =
          ExporterProgress.get_timestamps(
            timestamps_key,
            to_string(queue)
          )

        process_function.(http_response.body)
        |> maybe_remove_known_timestamps(timestamps, opts)

      {:error_limited, %{value: rate_limited_seconds}} ->
        do_handle_rate_limit(rate_limited_seconds, opts)
    end
  end

  defp execute_http_request(url, params) do
    headers = [{"authorization", "Apikey #{api_key()}"}]

    query_params = [
      market: params[:market],
      instrument: params[:instrument],
      to_ts: params[:timestamp],
      limit: params[:limit]
    ]

    url = url <> "?" <> URI.encode_query(query_params)

    HTTPoison.get(url, headers, recv_timeout: 15_000)
  end

  defp do_get_markets_and_instruments() do
    url = "https://data-api.cryptocompare.com/futures/v1/markets/instruments"
    headers = [{"authorization", "Apikey #{api_key()}"}]

    case HTTPoison.get(url, headers, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        market_mapped_instruments_map = parse_markets_instruments_response(body)

        {:ok, market_mapped_instruments_map}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("""
        [Cryptocompare Historical] Failed to get markets. Status code: #{status_code}. \
        Body: #{body}
        """)

        {:error, "Failed to get markets"}

      {:error, error} ->
        Logger.error("""
        [Cryptocompare Historical] Failed to get markets. Error: #{inspect(error)}
        """)

        {:error, "Failed to get markets"}
    end
  end

  @markets ~w[binance bitfinex bitmex bybit coinbase cryptodotcom kraken okex]
  defp parse_markets_instruments_response(json_body) do
    json_body
    |> Jason.decode!()
    |> Map.fetch!("Data")
    |> Enum.map(fn {market, data} ->
      mapped_instruments =
        data["instruments"]
        |> Enum.map(fn {instrument, _} -> instrument end)
        |> Enum.uniq()
        |> Enum.filter(fn instrument ->
          String.contains?(instrument, "PERPETUAL")
        end)

      {market, mapped_instruments}
    end)
    |> Enum.filter(fn {k, _} -> k in @markets end)
    |> Map.new()
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)

  defp maybe_remove_known_timestamps({:ok, list}, timestamps, opts) do
    # Filter out all the data points for which we already have data.
    # This works with the assumption that the data is exported in a
    # specific way. The API accepts a timestamp and a limit and returns
    # `limit` number of data points before `timestamp`. When this is done
    # a new job is scheduled with the timestamp of the earliest data point,
    # thus going back in history.

    min_timestamp = if list != [], do: Enum.min_by(list, & &1.timestamp).timestamp

    case Keyword.get(opts, :remove_known_timestamps, false) do
      false ->
        {:ok, min_timestamp, list}

      true ->
        list =
          case timestamps do
            nil -> list
            {min, max} -> list |> Enum.reject(&(&1.timestamp in min..max))
          end

        {:ok, min_timestamp, list}
    end
  end

  defp maybe_remove_known_timestamps({:error, error}, _timestamps, _opts), do: {:error, error}

  defp do_handle_rate_limit(rate_limited_seconds, opts) do
    module = Keyword.fetch!(opts, :module)
    oban_conf_name = module.conf_name()
    historical_scheduler = module.historical_scheduler()
    pause_resume_worker = module.pause_resume_worker()

    :ok = historical_scheduler.pause()

    data = pause_resume_worker.new(%{"type" => "resume"}, schedule_in: rate_limited_seconds)

    Oban.insert(oban_conf_name, data)

    {:error, :rate_limit}
  end
end
