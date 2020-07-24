defmodule Sanbase.Repo.Migrations.AddMetricsTable do
  @metric_module Application.compile_env(:sanbase, :metric_module)

  use Ecto.Migration

  def up() do
    setup()
    now = Timex.now()

    metrics =
      @metric_module.available_metrics()
      |> Enum.map(fn metric ->
        %{name: metric, inserted_at: now, updated_at: now}
      end)

    Sanbase.Repo.insert_all(@metric_module.MetricPostgresData, metrics)
  end

  def down(), do: :ok

  defp setup() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Application.ensure_all_started(:stripity_stripe)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
