defmodule Sanbase.Repo.Migrations.DeleteFromPriceMigrationTmp do
  use Ecto.Migration

  def up do
    setup()
    Sanbase.Repo.delete_all(Sanbase.PriceMigrationTmp)
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
