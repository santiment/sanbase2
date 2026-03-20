defmodule Sanbase.ExternalServices.Coinmarketcap.WebApi do
  use Tesla

  defstruct [:market_cap_by_available_supply, :price_usd, :volume_usd, :price_btc]

  require Logger

  import Sanbase.ExternalServices.Coinmarketcap.Utils, only: [wait_rate_limit: 2]

  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.ExternalServices.Coinmarketcap.{PricePoint, PriceScrapingProgress}
  alias Sanbase.Project

  @rate_limiting_server :graph_coinmarketcap_rate_limiter
  plug(Tesla.Middleware.Logger)
  plug(Sanbase.ExternalServices.RateLimiting.Middleware, name: @rate_limiting_server)
  plug(Sanbase.ExternalServices.ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://web-api.coinmarketcap.com")
  plug(Tesla.Middleware.Compression)

  @source "coinmarketcap"
  @prices_exporter :prices_exporter
  @max_rate_limit_retries 5

  @doc ~s"""
  Return the first datetime for which a given asset (a projct or the whole market)
  has data. Used when deciding the first datetime to start scraping from
  """
  @spec first_datetime(%Project{} | String.t()) :: {:ok, DateTime.t()} | {:error, any()}
  def first_datetime(%Project{} = project) do
    case LatestCoinmarketcapData.coinmarketcap_integer_id(project) do
      nil ->
        {:error,
         "Cannot fetch first datetime for #{Project.describe(project)}. Reason: Missing coinmarketcap integer id"}

      coinmarketcap_integer_id ->
        get_first_datetime(coinmarketcap_integer_id)
    end
  end

  def first_datetime("TOTAL_MARKET"), do: {:ok, ~U[2013-04-28T18:47:21.000Z]}

  defp get_first_datetime(id, retries \\ 0)

  defp get_first_datetime(id, retries) when retries >= @max_rate_limit_retries do
    error_msg =
      "[CMC] Max rate limit retries (#{@max_rate_limit_retries}) exceeded " <>
        "for get_first_datetime, CMC id #{id}"

    Logger.error(error_msg)

    # This should not really happen because we have wait_rate_limit/2.
    # If we reach here (retries exceeded) then probably there's some issue
    # with out rate limit waits
    Sentry.capture_message("CMC scraper max rate limit retries exceeded",
      level: :error,
      extra: %{identifier: id, operation: "get_first_datetime", retries: retries}
    )

    {:error, error_msg}
  end

  defp get_first_datetime(id, retries) do
    "https://api.coinmarketcap.com/data-api/v3/cryptocurrency/detail/chart?id=#{id}&range=ALL"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp, @rate_limiting_server)
        get_first_datetime(id, retries + 1)

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        json_decoded_body = body |> Jason.decode!()

        json_decoded_body
        |> get_in(["data", "points"])
        |> case do
          %{} = map ->
            map
            |> Map.keys()
            |> Enum.map(&String.to_integer/1)
            |> Enum.min()
            |> DateTime.from_unix()

          _ ->
            Logger.info([
              "[CMC] Cannot properly parse response from coinmarketcap: #{inspect(json_decoded_body)}"
            ])

            {:error, "Cannot parse the response from coinmarketcap for #{id}"}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_msg =
          "[CMC] Error fetching first datetime for id #{id}. " <>
            "Status: #{status}. Body: #{inspect(body, limit: 500)}"

        Logger.warning(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg =
          "[CMC] Error fetching first datetime for id #{id}. Reason: #{inspect(error)}"

        Logger.warning(error_msg)
        {:error, error_msg}
    end
  end

  def fetch_and_store_prices(%Project{} = project, %DateTime{} = last_fetched_datetime) do
    Logger.info("""
    [CMC] Fetching and storing prices for #{Project.describe(project)} with last fetched datetime #{last_fetched_datetime}
    """)

    case LatestCoinmarketcapData.coinmarketcap_integer_id(project) do
      nil ->
        :ok

      coinmarketcap_integer_id ->
        # Consume 10 price point intervals. Break early in case of errors.
        # Errors should not be ignored as this can cause a gap in the prices
        # in case the next fetch succeeds and we store a later progress datetime
        price_stream(coinmarketcap_integer_id, last_fetched_datetime, DateTime.utc_now())
        |> Stream.take(10)
        |> Enum.reduce_while(:ok, fn
          {:ok, result, interval}, acc ->
            store_price_points(project, result, interval)
            {:cont, acc}

          error, _acc ->
            {:halt, {:error, "Error in fetch_and_store_prices/2 for project: #{inspect(error)}"}}
        end)
    end
  end

  def fetch_and_store_prices("TOTAL_MARKET", last_fetched_datetime) do
    Logger.info(
      "[CMC] Fetching prices for TOTAL_MARKET with last fetched datetime #{last_fetched_datetime}"
    )

    # Consume 10 price point intervals. Break early in case of errors.
    # Errors should not be ignored as this can cause a gap in the prices
    # in case the next fetch succeeds and we store a later progress datetime
    price_stream("TOTAL_MARKET", last_fetched_datetime, DateTime.utc_now())
    |> Stream.take(10)
    |> Enum.reduce_while(:ok, fn
      {:ok, result, interval}, acc ->
        store_price_points("TOTAL_MARKET", result, interval)
        {:cont, acc}

      error, _acc ->
        {:halt, {:error, "Error in fetch_and_store_prices/2 for TOTAL_MARKET: #{inspect(error)}"}}
    end)
  end

  # In case there is gap in the data store the end of the interval. This is done
  # because in case of gaps the scraper can get stuck and rescrape the same
  # interval over and over again.
  defp store_price_points(%Project{slug: slug}, [], {from, to}) do
    Logger.warning(
      "[CMC] No price points returned for #{slug}, " <>
        "interval [#{DateTime.from_unix!(from)} - #{DateTime.from_unix!(to)}]. " <>
        "Advancing progress to avoid getting stuck."
    )

    to = max_dt_or_now(to)
    PriceScrapingProgress.store_progress(slug, @source, DateTime.from_unix!(to))
  end

  defp store_price_points("TOTAL_MARKET", [], {from, to}) do
    Logger.warning(
      "[CMC] No price points returned for TOTAL_MARKET, " <>
        "interval [#{DateTime.from_unix!(from)} - #{DateTime.from_unix!(to)}]. " <>
        "Advancing progress to avoid getting stuck."
    )

    to = max_dt_or_now(to)
    PriceScrapingProgress.store_progress("TOTAL_MARKET", @source, DateTime.from_unix!(to))
  end

  defp store_price_points(%Project{slug: slug} = project, price_points, _) do
    price_points = PricePoint.sanity_filters(price_points, slug)
    %{datetime: latest_datetime} = Enum.max_by(price_points, &DateTime.to_unix(&1.datetime))

    export_prices_to_kafka(project, price_points)

    PriceScrapingProgress.store_progress(slug, @source, latest_datetime)
  end

  defp store_price_points("TOTAL_MARKET", price_points, _) do
    price_points = PricePoint.sanity_filters(price_points, "TOTAL_MARKET")

    %{datetime: latest_datetime} = Enum.max_by(price_points, &DateTime.to_unix(&1.datetime))

    export_prices_to_kafka("TOTAL_MARKET", price_points)

    PriceScrapingProgress.store_progress("TOTAL_MARKET", @source, latest_datetime)
  end

  defp export_prices_to_kafka(%Project{slug: slug}, price_points) do
    Enum.map(price_points, fn point -> PricePoint.json_kv_tuple(point, slug) end)
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  end

  defp export_prices_to_kafka("TOTAL_MARKET", price_points) do
    Enum.map(price_points, fn point -> PricePoint.json_kv_tuple(point, "TOTAL_MARKET") end)
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  end

  def price_stream(identifier, %DateTime{} = from_datetime, %DateTime{} = to_datetime) do
    diff_seconds = DateTime.diff(to_datetime, from_datetime, :second)

    if diff_seconds < 3600 do
      Logger.info(
        "[CMC] Skipping price stream for #{identify(identifier)}, " <>
          "time range too short (#{diff_seconds}s)"
      )

      []
    else
      intervals_stream(from_datetime, to_datetime, days_step: 1)
      |> Stream.map(&extract_price_points_for_interval(identifier, &1))
    end
  end

  defp json_to_price_points(json, "TOTAL_MARKET", interval) do
    with {:ok, decoded} <- Jason.decode(json),
         %{
           "data" => %{"quotes" => quotes},
           "status" => %{"error_code" => "0"}
         } <- decoded do
      result =
        Enum.map(
          quotes || [],
          fn %{
               "quote" => [
                 %{
                   "timestamp" => datetime_iso8601,
                   "totalMarketCap" => marketcap_usd,
                   "totalVolume24H" => volume_usd
                 }
               ]
             } ->
            %PricePoint{
              marketcap_usd: marketcap_usd |> Sanbase.Math.to_integer(),
              volume_usd: volume_usd |> Sanbase.Math.to_integer(),
              datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime_iso8601)
            }
          end
        )

      {:ok, result, interval}
    else
      error -> handle_json_conversion_error("TOTAL_MARKET", error)
    end
  end

  defp json_to_price_points(json, identifier, interval) do
    with {:ok, decoded} <- Jason.decode(json),
         %{
           "data" => data,
           "status" => %{"error_code" => "0", "error_message" => "SUCCESS"}
         } <- decoded do
      result =
        Enum.map(
          data["points"] || [],
          fn
            {dt_unix_str, %{"v" => [price_usd, volume_usd, marketcap_usd, price_btc | _]}} ->
              dt_unix = String.to_integer(dt_unix_str)

              %PricePoint{
                price_usd: Sanbase.Math.to_float(price_usd),
                price_btc: Sanbase.Math.to_float(price_btc),
                marketcap_usd: Sanbase.Math.to_integer(marketcap_usd),
                volume_usd: Sanbase.Math.to_integer(volume_usd),
                datetime: DateTime.from_unix!(dt_unix)
              }

            data ->
              Logger.warning(
                "[CMC] No price points found for #{identify(identifier)}, " <>
                  "interval #{inspect(interval)}. Got: #{inspect(data, limit: 200)}"
              )

              nil
          end
        )
        |> Enum.reject(&is_nil/1)

      {:ok, result, interval}
    else
      error -> handle_json_conversion_error(identifier, error)
    end
  end

  defp handle_json_conversion_error(identifier, error) do
    case error do
      {:error, %Jason.DecodeError{} = decode_error} ->
        error_msg =
          "[CMC] Failed to decode JSON for #{identify(identifier)}: #{Exception.message(decode_error)}"

        Logger.error(error_msg)
        {:error, error_msg}

      %{"status" => %{"error_code" => code, "error_message" => msg}} ->
        error_msg =
          "[CMC] API error for #{identify(identifier)}: code=#{code}, message=#{msg}"

        Logger.error(error_msg)
        {:error, error_msg}

      other ->
        error_msg =
          "[CMC] Unexpected response for #{identify(identifier)}: #{inspect(other, limit: 500)}"

        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  defp extract_price_points_for_interval(identifier, interval) do
    do_extract_price_points(identifier, interval, _retries = 0)
  end

  defp do_extract_price_points(identifier, interval, retries)
       when retries >= @max_rate_limit_retries do
    error_msg =
      "[CMC] Max rate limit retries (#{@max_rate_limit_retries}) exceeded " <>
        "for #{identify(identifier)}, interval #{inspect(interval)}"

    Logger.error(error_msg)

    Sentry.capture_message("CMC scraper max rate limit retries exceeded",
      level: :error,
      extra: %{identifier: identifier, interval: interval, retries: retries}
    )

    {:error, error_msg}
  end

  defp do_extract_price_points("TOTAL_MARKET", {from_unix, to_unix}, _retries)
       when to_unix - from_unix < 3600 do
    Logger.info(
      "[CMC] Skipping price points extraction for TOTAL_MARKET, " <>
        "interval too short (#{to_unix - from_unix}s): " <>
        "[#{DateTime.from_unix!(from_unix)} - #{DateTime.from_unix!(to_unix)}]"
    )

    {:ok, [], {from_unix, to_unix}}
  end

  defp do_extract_price_points(
         "TOTAL_MARKET" = total_market,
         {from_unix, to_unix} = interval,
         retries
       ) do
    "https://api.coinmarketcap.com/data-api/v3/global-metrics/quotes/historical?format=chart&interval=5m&timeEnd=#{to_unix}&timeStart=#{from_unix}"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp, @rate_limiting_server)
        do_extract_price_points(total_market, interval, retries + 1)

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        json_to_price_points(body, total_market, interval)

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_msg =
          "[CMC] Error fetching data for TOTAL_MARKET. " <>
            "Status: #{status}. Body: #{inspect(body, limit: 500)}"

        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg =
          "[CMC] Error fetching data for TOTAL_MARKET. Reason: #{inspect(error)}"

        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  defp do_extract_price_points(id, {from_unix, to_unix}, _retries)
       when is_integer(id) and to_unix - from_unix < 3600 do
    Logger.info(
      "[CMC] Skipping price points extraction for CMC id #{id}, " <>
        "interval too short (#{to_unix - from_unix}s): " <>
        "[#{DateTime.from_unix!(from_unix)} - #{DateTime.from_unix!(to_unix)}]"
    )

    {:ok, [], {from_unix, to_unix}}
  end

  defp do_extract_price_points(id, {from_unix, to_unix} = interval, retries)
       when is_integer(id) do
    Logger.info(
      "[CMC] Extracting price points for CMC id #{id}, " <>
        "interval [#{DateTime.from_unix!(from_unix)} - #{DateTime.from_unix!(to_unix)}]"
    )

    "https://api.coinmarketcap.com/data-api/v3/cryptocurrency/detail/chart?id=#{id}&range=#{from_unix}~#{to_unix}"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp, @rate_limiting_server)
        do_extract_price_points(id, interval, retries + 1)

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        json_to_price_points(body, id, interval)

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_msg =
          "[CMC] Error fetching data for CMC id #{id}. " <>
            "Status: #{status}. Body: #{inspect(body, limit: 500)}"

        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg =
          "[CMC] Error fetching data for CMC id #{id}. Reason: #{inspect(error)}"

        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  defp identify(id) when is_integer(id), do: "CMC id #{id}"
  defp identify(str) when is_binary(str), do: str

  # Return a stream of intervals in the from {from_unix, to_unix} for the
  # time between from and two with opts[:days_step] intervals
  defp intervals_stream(%DateTime{} = from, %DateTime{} = to, opts) do
    days_step = Keyword.get(opts, :days_step, 1)

    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    to_unix = Enum.min([to_unix, now_unix])

    Stream.unfold(from_unix, fn start_unix ->
      if start_unix < to_unix do
        end_unix = start_unix + 86_400 * days_step
        end_unix = Enum.min([end_unix, now_unix])

        if end_unix - start_unix < 60 do
          nil
        else
          {{start_unix, end_unix}, end_unix}
        end
      else
        nil
      end
    end)
  end

  defp max_dt_or_now(%DateTime{} = dt) do
    Enum.max_by([dt, DateTime.utc_now()], &DateTime.to_unix/1)
  end

  defp max_dt_or_now(seconds) when is_integer(seconds) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    Enum.max([seconds, now_unix])
  end
end
