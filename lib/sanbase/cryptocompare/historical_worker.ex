defmodule Sanbase.Cryptocompare.HistoricalWorker do
  @moduledoc ~s"""
  An Oban Worker that processes the jobs in the cryptocompare_historical_jobs_queue
  queue.

  An Oban Worker has one main function `perform/1` which receives as argument
  one record from the oban jobs table. If it returns :ok or {:ok, _}, then the
  job is considered successful and is completed. In order to have retries in case
  of Kafka downtime, the export to Kafka is done via persist_sync/2. This guarantees
  that if get_data/3 and export_data/1 return :ok, then the data is in Kafka.

  If perform/1 returns :error or {:error, _} then the task is scheduled for retry.
  An exponential backoff algorithm is used in order to decide when to retry. The
  default 20 attempts and the default algorithm used first retry after some seconds
  and the last attempt is done after about 3 weeks.
  """
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_queue,
    unique: [period: 60 * 86_400]

  import Sanbase.Cryptocompare.HTTPHeaderUtils, only: [parse_value_list: 1]

  require Logger
  require Sanbase.Utils.Config, as: Config

  @url "https://min-api.cryptocompare.com/data/histo/minute/daily"

  def queue(), do: :cryptocompare_historical_jobs_queue

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"quote_asset" => quote_asset}})
      when quote_asset not in ["USD", "BTC"] do
    # TODO: Remove once all the USD and BTC pairs are done
    # In order to priroritize the jobs that are more important, snooze
    # the jobs that are not having USD or BTC quote asset.
    {:snooze, 86_400}
  end

  def perform(%Oban.Job{args: args}) do
    %{"base_asset" => base_asset, "quote_asset" => quote_asset, "date" => date} = args

    t1 = System.monotonic_time(:millisecond)
    should_snooze? = base_asset not in available_base_assets()
    t2 = System.monotonic_time(:millisecond)

    case should_snooze? do
      true ->
        {:snooze, 86_400}

      false ->
        case get_data(base_asset, quote_asset, date) do
          {:ok, data} ->
            t3 = System.monotonic_time(:millisecond)
            result = export_data(data)
            t4 = System.monotonic_time(:millisecond)

            Logger.info(
              "[Cryptocompare Historical] Time took to perform a job. " <>
                inspect({t2 - t1, t3 - t2, t4 - t3})
            )

            result

          {:error, error} ->
            {:error, error}
        end
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  # Private functions

  defp available_base_assets() do
    # TODO: Remove once all the used assets are scrapped
    # In order to priroritize the jobs that are more important, snooze
    # the jobs that are not having a base asset that is stored in our DBs.
    cache_key = {__MODULE__, :available_base_assets}

    {:ok, assets} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        data =
          Sanbase.Model.Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
          |> Enum.map(&elem(&1, 0))

        {:ok, data}
      end)

    assets
  end

  @spec get_data(any, any, any) :: {:error, HTTPoison.Error.t()} | {:ok, any}
  def get_data(base_asset, quote_asset, date) do
    query_params = [
      fsym: base_asset,
      tsym: quote_asset,
      e: "CCCAGG",
      date: date
    ]

    headers = [{"authorization", "Apikey #{api_key()}"}]

    url = @url <> "?" <> URI.encode_query(query_params)

    t1 = System.monotonic_time(:millisecond)

    case HTTPoison.get(url, headers, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body} = resp} ->
        t2 = System.monotonic_time(:millisecond)

        case rate_limited?(resp) do
          false ->
            t3 = System.monotonic_time(:millisecond)

            result = csv_to_ohlcv_list(body)
            t4 = System.monotonic_time(:millisecond)

            Logger.info(
              "[Cryptocompare Historical] Time took to get data. " <>
                inspect({t2 - t1, t3 - t2, t4 - t3})
            )

            result

          biggest_rate_limited_window ->
            handle_rate_limit(resp, biggest_rate_limited_window)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp rate_limited?(resp) do
    zero_remainings =
      get_header(resp, "X-RateLimit-Remaining-All")
      |> elem(1)
      |> parse_value_list()
      |> Enum.filter(&(&1.value == 0))

    case zero_remainings do
      [] -> false
      list -> Enum.max_by(list, & &1.time_period).time_period
    end
  end

  defp handle_rate_limit(resp, biggest_rate_limited_window) do
    Sanbase.Cryptocompare.HistoricalScheduler.pause()

    header_value =
      get_header(resp, "X-RateLimit-Reset-All")
      |> elem(1)

    Logger.info(
      "[Cryptocompare Historical] Rate limited. X-RateLimit-Reset-All header: #{header_value}"
    )

    reset_after_seconds =
      header_value
      |> parse_value_list()
      |> Enum.find(&(&1.time_period == biggest_rate_limited_window))
      |> Map.get(:value)

    %{"type" => "resume"}
    |> Sanbase.Cryptocompare.PauseResumeWorker.new(schedule_in: reset_after_seconds)
    |> Oban.insert()

    {:error, :rate_limit}
  end

  defp get_header(%HTTPoison.Response{} = resp, header) do
    Enum.find(resp.headers, &match?({^header, _}, &1))
  end

  defp csv_to_ohlcv_list(data) do
    [_headers | rest] = data |> String.trim() |> CSVLixir.parse()

    result = Enum.map(rest, &csv_line_to_point/1)

    case Enum.find_index(result, &(&1 == :error)) do
      nil -> {:ok, result}
      _index -> {:error, "[Cryptocompare Historical] NaN values found in place of prices"}
    end
  end

  defp csv_line_to_point([time, fsym, tsym, o, h, l, c, vol_from, vol_to] = list) do
    case Enum.any?(list, &(&1 == "NaN")) do
      true ->
        :error

      false ->
        [o, h, l, c, vol_from, vol_to] =
          [o, h, l, c, vol_from, vol_to] |> Enum.map(&Sanbase.Math.to_float/1)

        %{
          source: "cryptocompare",
          interval_seconds: 60,
          datetime: time |> String.to_integer() |> DateTime.from_unix!(),
          base_asset: fsym,
          quote_asset: tsym,
          open: o,
          high: h,
          low: l,
          close: c,
          volume_from: vol_from,
          volume_to: vol_to
        }
    end
  end

  defp csv_line_to_point([time, "CCCAGG", fsym, tsym, c, h, l, o, vol_from, vol_to]) do
    csv_line_to_point([time, fsym, tsym, o, h, l, c, vol_from, vol_to])
  end

  @asset_ohlcv_price_pairs_topic_exporter :asset_ohlcv_price_pairs_exporter
  @asset_price_pairs_only_exporter :asset_price_pairs_only_exporter

  defp export_data(data) do
    export_asset_ohlcv_price_pairs_topic(data)
    export_asset_price_pairs_only_topic(data)
  end

  defp export_asset_ohlcv_price_pairs_topic(data) do
    data
    |> Enum.map(&to_ohlcv_price_point/1)
    |> Sanbase.KafkaExporter.persist_sync(@asset_ohlcv_price_pairs_topic_exporter)
  end

  defp export_asset_price_pairs_only_topic(data) do
    data
    |> Enum.map(&to_price_only_point/1)
    |> Sanbase.KafkaExporter.persist_sync(@asset_price_pairs_only_exporter)
  end

  defp to_ohlcv_price_point(point) do
    point
    |> Sanbase.Cryptocompare.OHLCVPricePoint.new()
    |> Sanbase.Cryptocompare.OHLCVPricePoint.json_kv_tuple()
  end

  defp to_price_only_point(point) do
    %{
      price: point.close,
      datetime: point.datetime,
      base_asset: point.base_asset,
      quote_asset: point.quote_asset,
      source: point.source
    }
    |> Sanbase.Cryptocompare.PriceOnlyPoint.new()
    |> Sanbase.Cryptocompare.PriceOnlyPoint.json_kv_tuple()
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)
end
