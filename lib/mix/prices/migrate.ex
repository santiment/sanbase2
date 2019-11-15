defmodule Sanbase.Prices.Migrate do
  require Integer
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Prices.Store, as: PricesStore
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint

  @chunk_days 20

  def run() do
    projects = Project.List.projects()
    Logger.info("Migrating prices from influxdb for count: #{length(projects)} projects")

    projects
    |> Enum.map(fn %Project{ticker: ticker, slug: slug} -> ticker <> "_" <> slug end)
    |> Enum.chunk_every(20)
    |> Enum.flat_map(&first_datetimes/1)
    |> Enum.each(&get_prices_and_persist_in_kafka/1)
  end

  def get_prices_and_persist_in_kafka({measurement, first_datetime_iso}) do
    slug = String.split(measurement, "_", parts: 2) |> List.last()
    {:ok, first_datetime, _} = DateTime.from_iso8601(first_datetime_iso)
    now = Timex.now()

    chunk_datetimes(first_datetime, now)
    |> Enum.each(fn [from, to] ->
      get_prices(measurement, from, to)
      |> Enum.map(&PricePoint.to_json(&1, slug))
      |> Sanbase.KafkaExporter.persist(:prices_exporter)
    end)
  end

  def first_datetimes(measurements) do
    PricesStore.first_datetime_multiple_measurements(measurements)
    |> case do
      {:ok, datetimes} ->
        datetimes

      _ ->
        []
    end
  end

  def chunk_datetimes(first_datetime, now) do
    Stream.unfold(first_datetime, fn dt ->
      if DateTime.compare(dt, now) == :lt do
        {dt, Timex.shift(dt, days: @chunk_days)}
      else
        nil
      end
    end)
    |> Enum.to_list()
    |> List.insert_at(-1, now)
    |> Enum.chunk_every(2, 1, :discard)
  end

  def get_prices(measurement, from, to) do
    PricesStore.fetch_price_points!(measurement, from, to)
    |> Enum.map(fn [dt, price_usd, price_btc, marketcap_usd, volume_usd] ->
      %PricePoint{
        datetime: dt,
        price_usd: price_usd,
        price_btc: price_btc,
        volume_usd: volume_usd,
        marketcap_usd: marketcap_usd
      }
    end)
  end
end
