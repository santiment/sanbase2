defmodule Sanbase.Cryptocompare.HistoricalWorker do
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_queue,
    unique: [period: 30 * 24 * 60 * 60]

  require Sanbase.Utils.Config, as: Config

  @url "https://min-api.cryptocompare.com/data/histo/minute/daily"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"base_asset" => base_asset, "quote_asset" => quote_asset, "date" => date} = args

    case get_data(base_asset, quote_asset, date) do
      {:ok, data} ->
        export_data(data)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  # Private functions

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

    case HTTPoison.get(url, headers, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        csv_to_ohlcv_list(body)

      {:error, error} ->
        {:error, error}
    end
  end

  defp csv_to_ohlcv_list(data) do
    [_headers | rest] = data |> String.trim() |> CSVLixir.read()

    result = Enum.map(rest, &csv_line_to_point/1)

    case Enum.find_index(result, &(&1 == :error)) do
      nil -> {:ok, result}
      _index -> {:error, "[Cryptocompare Historical] NaN values found in place of prices"}
    end
  end

  defp csv_line_to_point([_, _, _, "NaN", "NaN", "NaN", "NaN", _, _]), do: :error

  defp csv_line_to_point([time, fsym, tsym, o, h, l, c, vol_from, vol_to]) do
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

  defp csv_line_to_point([time, "CCCAGG", fsym, tsym, c, h, l, o, vol_from, vol_to]) do
    csv_line_to_point([time, fsym, tsym, o, h, l, c, vol_from, vol_to])
  end

  @asset_ohlcv_price_pairs_topic_exporter :asset_ohlcv_price_pairs_exporter

  defp export_data(data) do
    data
    |> Enum.map(&to_ohlcv_price_point/1)
    |> Sanbase.KafkaExporter.persist_sync(@asset_ohlcv_price_pairs_topic_exporter)
  end

  defp to_ohlcv_price_point(point) do
    point
    |> Sanbase.Cryptocompare.OHLCVPricePoint.new()
    |> Sanbase.Cryptocompare.OHLCVPricePoint.json_kv_tuple()
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)
end
