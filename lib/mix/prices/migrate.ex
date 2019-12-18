defmodule Sanbase.PriceMigrationTmp do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sabase.Model.Project

  schema "price_migration_tmp" do
    field(:slug, :string)
    field(:is_migrated, :boolean)
    field(:progress, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = price_migration_tmp, attrs \\ %{}) do
    price_migration_tmp
    |> cast(attrs, [
      :slug,
      :is_migrated,
      :progress
    ])
  end

  def create!(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert!()
  end

  def all_migrated do
    from(
      pmt in __MODULE__,
      where: not is_nil(pmt.slug) and pmt.is_migrated,
      select: pmt.slug
    )
    |> Repo.all()
  end
end

defmodule Sanbase.Prices.Migrate do
  require Integer
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store, as: PricesStore
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.PriceMigrationTmp

  @chunk_days 10
  @migration_exporter :migrate_influxdb_prices
  @topic "asset_prices"

  def run(from_iso) do
    setup()

    {time_microsec, _} = :timer.tc(fn -> do_work(from_iso) end)

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

  def not_migrated_projects do
    migrated_projects = PriceMigrationTmp.all_migrated()

    all_projects =
      Project.List.projects_with_source("coinmarketcap", include_hidden_projects?: true)

    all_projects = [%Project{ticker: "TOTAL_MARKET", slug: "total-market"} | all_projects]

    all_projects
    |> Enum.sort_by(& &1.slug)
    |> Enum.reject(&(&1.slug == "total-market" and "TOTAL_MARKET" in migrated_projects))
    |> Enum.reject(&(&1.slug in migrated_projects))
  end

  defp do_work(from_iso) do
    projects = not_migrated_projects()
    all_projects_count = length(projects)
    Logger.info("Migrating prices from influxdb for count: #{all_projects_count} projects")

    projects
    |> Enum.map(&{Sanbase.Influxdb.Measurement.name_from(&1), from_iso})
    |> Enum.reduce(1, fn {measurement, first_datetime_iso}, current_project_count ->
      Logger.info("Start migrating #{measurement} from #{from_iso}")

      {time_microsec, result} =
        :timer.tc(fn -> get_prices_and_persist_in_kafka({measurement, first_datetime_iso}) end)

      {is_migrated, result_msg} =
        result
        |> Enum.filter(fn {_measurement, _dates, result} -> result != :ok end)
        |> case do
          [] -> {true, "ok"}
          errors -> {false, "with errors: #{inspect(errors)}"}
        end

      progress =
        "Migrating #{measurement} finished #{result_msg} in #{time_microsec / 1_000_000}s. Progress #{
          current_project_count
        } / #{all_projects_count}"

      Logger.info(progress)

      PriceMigrationTmp.create!(%{
        slug: slug_from_measurement(measurement),
        is_migrated: is_migrated,
        progress: progress
      })

      current_project_count + 1
    end)
  end

  defp get_prices_and_persist_in_kafka({measurement, first_datetime_iso}) do
    slug = slug_from_measurement(measurement)
    {:ok, first_datetime, _} = DateTime.from_iso8601(first_datetime_iso)
    now = Timex.now()

    chunk_datetimes(first_datetime, now)
    |> Enum.map(fn [from, to] ->
      result =
        get_prices(measurement, from, to)
        |> Enum.map(&PricePoint.json_kv_tuple(&1, slug))
        |> Sanbase.KafkaExporter.persist_sync(@migration_exporter)

      {measurement, {first_datetime, now}, result}
    end)
  end

  def first_datetimes(measurements) do
    {measurements, total_market_datetimes} =
      if "TOTAL_MARKET_total-market" in measurements do
        {Enum.reject(measurements, &(&1 == "TOTAL_MARKET_total-market")),
         first_datetimes_total_market()}
      else
        {measurements, []}
      end

    PricesStore.first_datetime_multiple_measurements(measurements)
    |> case do
      {:ok, datetimes} ->
        datetimes ++ total_market_datetimes

      error ->
        Logger.error(
          "PricesStore.first_datetime_multiple_measurements error on projects #{
            inspect(measurements)
          }, #{inspect(error)}"
        )

        []
    end
  end

  defp first_datetimes_total_market() do
    PricesStore.first_datetime_total_market(["TOTAL_MARKET_total-market"])
    |> case do
      {:ok, datetimes} ->
        datetimes

      error ->
        Logger.error(
          "PricesStore.first_datetime_multiple_measurements error on projects #{
            inspect("TOTAL_MARKET_total-market")
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

  defp slug_from_measurement("TOTAL_MARKET_total-market") do
    "TOTAL_MARKET"
  end

  defp slug_from_measurement(measurement) do
    String.split(measurement, "_")
    |> List.last()
  end
end
