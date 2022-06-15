defmodule Sanbase.Repo.Migrations.AddMetricsTable do
  use Ecto.Migration

  def up() do
    setup()
    now = Timex.now()

    metrics =
      Sanbase.Metric.available_metrics()
      |> Enum.map(fn metric ->
        %{name: metric, inserted_at: now, updated_at: now}
      end)

    Sanbase.Repo.insert_all(Sanbase.Metric.MetricPostgresData, metrics)
  end

  def down(), do: :ok

  defp setup() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:stripity_stripe)
  end
end
