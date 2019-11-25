defmodule Sanbase.Prices.Migrate do
  require Integer
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store, as: PricesStore
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint

  @chunk_days 20
  @migration_exporter :migrate_influxdb_prices
  @topic "asset_prices"

  def run() do
    setup()

    {time_microsec, _} = :timer.tc(fn -> do_work() end)

    progress = "Migrating all projects finished in #{time_microsec / 1_000_000}s"
    Logger.info(progress)
  end

  defp setup() do
    Sanbase.KafkaExporter.start_link(
      name: @migration_exporter,
      buffering_max_messages: 0,
      kafka_flush_timeout: 10_000,
      can_send_after_interval: 100,
      topic: @topic
    )
  end

  def do_work() do
    projects = Project.List.projects()
    all_projects_count = length(projects)
    Logger.info("Migrating prices from influxdb for count: #{all_projects_count} projects")

    projects
    |> Enum.map(&Sanbase.Influxdb.Measurement.name_from/1)
    |> Enum.chunk_every(50)
    |> Enum.flat_map(&first_datetimes/1)
    |> Enum.reduce(1, fn {measurement, first_datetime_iso}, current_project_count ->
      Logger.info("Start migrating #{measurement}")

      {time_microsec, result} =
        :timer.tc(fn -> get_prices_and_persist_in_kafka({measurement, first_datetime_iso}) end)

      result_msg =
        result
        |> Enum.filter(fn {_measurement, _dates, result} -> result != :ok end)
        |> case do
          [] -> "ok"
          errors -> "with errors: #{inspect(errors)}"
        end

      progress =
        "Migrating #{measurement} finished #{result_msg} in #{time_microsec / 1_000_000}s. Progress #{
          current_project_count
        } / #{all_projects_count}"

      Logger.info(progress)

      current_project_count + 1
    end)
  end

  defp get_prices_and_persist_in_kafka({measurement, first_datetime_iso}) do
    slug = String.split(measurement, "_", parts: 2) |> List.last()
    {:ok, first_datetime, _} = DateTime.from_iso8601(first_datetime_iso)
    now = Timex.now()

    chunk_datetimes(first_datetime, now)
    |> Enum.map(fn [from, to] ->
      result =
        get_prices(measurement, from, to)
        |> Enum.map(&PricePoint.to_json(&1, slug))
        |> Sanbase.KafkaExporter.persist_sync(@migration_exporter)

      {measurement, {first_datetime, now}, result}
    end)
  end

  defp first_datetimes(measurements) do
    PricesStore.first_datetime_multiple_measurements(measurements)
    |> case do
      {:ok, datetimes} ->
        datetimes

      error ->
        Logger.error(
          "PricesStore.first_datetime_multiple_measurements error on projects #{
            inspect(measurements)
          }, #{inspect(error)}"
        )

        []
    end
  end

  defp chunk_datetimes(first_datetime, now) do
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

  defp get_prices(measurement, from, to) do
    PricesStore.fetch_price_points(measurement, from, to)
    |> case do
      {:ok, result} ->
        result
        |> Enum.map(fn [dt, price_usd, price_btc, marketcap_usd, volume_usd] ->
          %PricePoint{
            datetime: dt,
            price_usd: price_usd,
            price_btc: price_btc,
            volume_usd: volume_usd,
            marketcap_usd: marketcap_usd
          }
        end)

      {:error, error} ->
        Logger.error(
          "PricesStore.fetch_price_points error on project #{measurement}, #{inspect(error)}"
        )

        []
    end
  end
end
