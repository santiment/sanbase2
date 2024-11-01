defmodule Sanbase.Repo.Migrations.PopulateMetricRegistry do
  use Ecto.Migration

  def up do
    Sanbase.Metric.Registry.Populate.run()
  end

  def down do
    Sanbase.Repo.delete(Sanbase.Metric.Registry)
  end
end
