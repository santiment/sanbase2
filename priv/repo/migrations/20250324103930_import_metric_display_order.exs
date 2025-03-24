defmodule Sanbase.Repo.Migrations.ImportMetricDisplayOrder do
  use Ecto.Migration
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Repo

  import Ecto.Query

  def up do
    setup()

    file = Path.join(__DIR__, "ui_metrics_metadata.json")

    case DisplayOrder.import_from_json_file(file) do
      {:ok, stats} ->
        IO.puts("Successfully imported metric display order data from JSON.")

        IO.puts(
          "Inserted: #{stats.inserted}, Existing: #{stats.existing}, Failed: #{stats.failed}"
        )

        if stats.failed > 0 do
          IO.puts("\nFailed metrics:")

          Enum.each(stats.failed_metrics, fn failed ->
            IO.puts(
              "- #{failed.metric} (#{failed.category}/#{failed.group || "no group"}): #{failed.reason}"
            )
          end)
        end

        if map_size(stats.duplicates) > 0 do
          IO.puts("\nDuplicate metrics found in JSON file:")

          Enum.each(stats.duplicates, fn {metric_name, occurrences} ->
            locations =
              Enum.map_join(occurrences, ", ", fn %{category: c, group: g} ->
                "#{c}/#{g || "no group"}"
              end)

            IO.puts("- #{metric_name} appears in: #{locations}")
          end)
        end

      {:error, reason} ->
        IO.puts("Error importing metric display order data: #{inspect(reason)}")
    end
  end

  def down do
    setup()

    IO.puts("Removing metric display order data imported from JSON...")

    {count, _} = from(m in "metric_display_order") |> Repo.delete_all()
    IO.puts("Removed #{count} metric display order records")
  end

  defp setup do
    # Ensure all required applications are started
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:con_cache)
    Application.ensure_all_started(:jason)

    # Initialize specific ConCache instances needed for the registry
    # This is crucial - the error happens because the cache process doesn't exist

    # Start sanbase generic cache
    ConCache.start_link(
      name: :sanbase_cache,
      ttl_check_interval: :timer.seconds(30),
      global_ttl: :timer.minutes(5),
      acquire_lock_timeout: 60_000
    )

    # Give the processes time to initialize
    Process.sleep(1000)

    IO.puts("ConCache caches initialized successfully")
  end
end
