defmodule Sanbase.ExternalServices.Coinmarketcap.WebApi do
  defstruct [:market_cap_by_available_supply, :price_usd, :volume_usd, :price_btc]

  require Logger

  use Tesla

  alias Sanbase.Model.LatestCoinmarketcapData
  alias Sanbase.ExternalServices.Coinmarketcap.{PricePoint, PriceScrapingProgress}
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store

  @rate_limiting_server :graph_coinmarketcap_rate_limiter
  plug(Sanbase.ExternalServices.RateLimiting.Middleware, name: @rate_limiting_server)
  plug(Sanbase.ExternalServices.ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://web-api.coinmarketcap.com")
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  @source "coinmarketcap"
  @prices_exporter :prices_exporter
  @total_market_measurement "TOTAL_MARKET_total-market"
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

  def first_datetime("TOTAL_MARKET"),
    do: {:ok, ~U[2013-04-28T18:47:21.000Z]}

  defp get_first_datetime(nil), do: {:error, "Project does not have coinmarketcap integer id"}

  defp get_first_datetime(id) do
    "/v1.1/cryptocurrency/quotes/historical?format=chart_crypto_details&id=#{id}&time_start=2009-01-01"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp)
        get_first_datetime(id)

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        body
        |> Jason.decode!()
        |> get_in(["status", "timestamp"])
        |> case do
          bin_ts when is_binary(bin_ts) -> {:ok, Sanbase.DateTimeUtils.from_iso8601!(bin_ts)}
          _ -> {:error, "[CMC] Error fetching first datetime for #{id}."}
        end

      {:ok, %Tesla.Env{status: 400, body: body}} ->
        body
        |> Jason.decode!()
        |> get_in(["status", "error_message"])
        |> String.split(" ")
        |> Enum.map(&DateTime.from_iso8601/1)
        |> Enum.find(&match?({:ok, _, _}, &1))
        |> case do
          {:ok, %DateTime{} = first_datetime, _} -> {:ok, first_datetime}
          _ -> {:error, "[CMC] Error fetching first datetime for #{id}."}
        end

      error ->
        Logger.warn("[CMC] Error fetching first datetime for #{id}. Reason: #{inspect(error)}")
        {:error, "[CMC] Error fetching first datetime for #{id}"}
    end
  end

  def fetch_and_store_prices(%Project{} = project, %DateTime{} = last_fetched_datetime) do
    Logger.info("""
    [CMC] Fetching and storing prices for #{Project.describe(project)} with last fetched datetime #{
      last_fetched_datetime
    }
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
        |> Enum.reduce_while(%{}, fn
          {:ok, result, interval}, acc ->
            store_price_points(project, result, interval)
            {:cont, acc}

          _, acc ->
            {:halt, acc}
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
    |> Enum.reduce_while(%{}, fn
      {:ok, result, interval}, acc ->
        store_price_points("TOTAL_MARKET", result, interval)
        {:cont, acc}

      _, acc ->
        {:halt, acc}
    end)
  end

  # In case there is gap in the data store the end of the interval. This is done
  # because in case of gaps the scraper can get stuck and rescrape the same
  # interval over and over again.
  defp store_price_points(%Project{slug: slug}, [], {_, to}) do
    to = max_dt_or_now(to)
    PriceScrapingProgress.store_progress(slug, @source, DateTime.from_unix!(to))
  end

  defp store_price_points("TOTAL_MARKET", [], {_, to}) do
    to = max_dt_or_now(to)
    PriceScrapingProgress.store_progress("TOTAL_MARKET", @source, DateTime.from_unix!(to))
  end

  defp store_price_points(%Project{slug: slug} = project, price_points, _) do
    price_points = PricePoint.sanity_filters(price_points)
    %{datetime: latest_datetime} = Enum.max_by(price_points, &DateTime.to_unix(&1.datetime))

    export_prices_to_kafka(project, price_points)

    if Application.get_env(:sanbase, :influx_store_enabled, true) do
      export_prices_to_influxdb(Measurement.name_from(project), price_points)
    end

    PriceScrapingProgress.store_progress(slug, @source, latest_datetime)
  end

  defp store_price_points("TOTAL_MARKET", price_points, _) do
    price_points = PricePoint.sanity_filters(price_points)

    %{datetime: latest_datetime} = Enum.max_by(price_points, &DateTime.to_unix(&1.datetime))

    export_prices_to_kafka("TOTAL_MARKET", price_points)

    # The influxdb TOTAL_MARKET measurement has float types
    price_points =
      Enum.map(
        price_points,
        fn %PricePoint{marketcap_usd: marketcap_usd, volume_usd: volume_usd} = point ->
          %PricePoint{
            point
            | marketcap_usd: marketcap_usd |> Sanbase.Math.to_float(),
              volume_usd: volume_usd |> Sanbase.Math.to_float()
          }
        end
      )

    if Application.get_env(:sanbase, :influx_store_enabled, true) do
      export_prices_to_influxdb(@total_market_measurement, price_points)
    end

    PriceScrapingProgress.store_progress("TOTAL_MARKET", @source, latest_datetime)
  end

  defp export_prices_to_influxdb(measurement, price_points) do
    price_points
    |> Enum.flat_map(&PricePoint.price_points_to_measurements(&1, measurement))
    |> Store.import()
  end

  defp export_prices_to_kafka(%Project{slug: slug}, price_points) do
    Enum.map(price_points, fn point -> PricePoint.json_kv_tuple(point, slug) end)
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  end

  defp export_prices_to_kafka("TOTAL_MARKET", price_points) do
    Enum.map(price_points, fn point -> PricePoint.json_kv_tuple(point, "TOTAL_MARKET") end)
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  end

  def price_stream(identifier, from_datetime, to_datetime) do
    intervals_stream(from_datetime, to_datetime, days_step: 10)
    |> Stream.map(&extract_price_points_for_interval(identifier, &1))
  end

  defp json_to_price_points(json, "TOTAL_MARKET", interval) do
    with {:ok, decoded} <- Jason.decode(json),
         %{
           "data" => data,
           "status" => %{"error_code" => 0, "error_message" => nil}
         } <- decoded do
      result =
        Enum.map(data, fn {datetime_iso8601, [marketcap_usd, volume_usd]} ->
          %PricePoint{
            marketcap_usd: marketcap_usd |> Sanbase.Math.to_integer(),
            volume_usd: volume_usd |> Sanbase.Math.to_integer(),
            datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime_iso8601)
          }
        end)

      {:ok, result, interval}
    else
      _ -> {:error, "Error converting JSON for TOTAL_MARKET to price points"}
    end
  end

  defp json_to_price_points(json, identifier, interval) do
    with {:ok, decoded} <- Jason.decode(json),
         %{
           "data" => data,
           "status" => %{"error_code" => 0, "error_message" => nil}
         } <- decoded do
      result =
        Enum.map(
          data,
          fn
            {datetime_iso8601,
             %{"BTC" => [price_btc], "USD" => [price_usd, volume_usd, marketcap_usd]}} ->
              %PricePoint{
                price_usd: price_usd |> Sanbase.Math.to_float(),
                price_btc: price_btc |> Sanbase.Math.to_float(),
                marketcap_usd: marketcap_usd |> Sanbase.Math.to_integer(),
                volume_usd: volume_usd |> Sanbase.Math.to_integer(),
                datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime_iso8601)
              }

            {_, _} ->
              nil
          end
        )
        |> Enum.reject(&is_nil/1)

      {:ok, result, interval}
    else
      _ -> {:error, "Error converting JSON for #{identifier} to price points"}
    end
  end

  defp extract_price_points_for_interval(
         "TOTAL_MARKET" = total_market,
         {from_unix, to_unix} = interval
       ) do
    Logger.info("""
      [CMC] Extracting price points for TOTAL_MARKET and interval [#{
      DateTime.from_unix!(from_unix)
    } - #{DateTime.from_unix!(to_unix)}]
    """)

    "/v1.1/global-metrics/quotes/historical?format=chart&interval=5m&time_start=#{from_unix}&time_end=#{
      to_unix
    }"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp)
        extract_price_points_for_interval(total_market, interval)

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        json_to_price_points(body, total_market, interval)

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = "[CMC] Error fetching data for TOTAL_MARKET. Status code: #{status}"
        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = "[CMC] Error fetching data for TOTAL_MARKET. Reason: #{inspect(error)}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  defp extract_price_points_for_interval(id, {from_unix, to_unix} = interval)
       when is_integer(id) do
    Logger.info("""
      [CMC] Extracting price points for coinmarketcap integer id #{id} and interval [#{
      DateTime.from_unix!(from_unix)
    } - #{DateTime.from_unix!(to_unix)}]
    """)

    "/v1.1/cryptocurrency/quotes/historical?convert=USD,BTC&format=chart_crypto_details&id=#{id}&time_start=#{
      from_unix
    }&time_end=#{to_unix}"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp)
        extract_price_points_for_interval(id, interval)

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        json_to_price_points(body, id, interval)

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = """
        [CMC] Error fetching data for project with coinmarketcap integer id #{id}. Status code: #{
          status
        }
        """

        Logger.error(error_msg)

        {:error, error_msg}

      {:error, error} ->
        error_msg = """
        [CMC] Error fetching data for coinmarketcap integer id #{id}. Reason: #{inspect(error)}
        """

        Logger.error(error_msg)

        {:error, error_msg}
    end
  end

  # Return a stream of intervals in the from {from_unix, to_unix} for the
  # time between from and two with opts[:days_step] intervals
  defp intervals_stream(%DateTime{} = from, %DateTime{} = to, opts) do
    days_step = Keyword.get(opts, :days_step, 1)

    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    Stream.unfold(from_unix, fn start_unix ->
      if start_unix <= to_unix do
        end_unix = start_unix + 86_400 * days_step
        {{start_unix, end_unix}, end_unix}
      else
        nil
      end
    end)
  end

  # After invocation of this function the process should execute `Process.exit(self(), :normal)`
  # There is no meaningful result to be returned here. If it does not exit
  # this case should return a special case and it should be handeled so the
  # `last_updated` is not updated when no points are written
  defp wait_rate_limit(%Tesla.Env{status: 429, headers: headers}) do
    wait_period =
      case Enum.find(headers, &match?({"retry-after", _}, &1)) do
        {_, wait_period} -> wait_period |> String.to_integer()
        _ -> 1
      end

    wait_until = Timex.shift(Timex.now(), seconds: wait_period)
    Sanbase.ExternalServices.RateLimiting.Server.wait_until(@rate_limiting_server, wait_until)
  end

  defp max_dt_or_now(%DateTime{} = dt) do
    Enum.max_by([dt, DateTime.utc_now()], &DateTime.to_unix/1)
  end

  defp max_dt_or_now(seconds) when is_integer(seconds) do
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    Enum.max([seconds, now_unix])
  end
end
