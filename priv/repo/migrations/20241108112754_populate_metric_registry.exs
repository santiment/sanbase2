defmodule Sanbase.Repo.Migrations.PopulateMetricRegistry do
  @moduledoc false
  use Ecto.Migration

  def up do
    Sanbase.Metric.Registry.Populate.run()
  end

  def down do
    Sanbase.Repo.delete_all(Sanbase.Metric.Registry)
  end
end
