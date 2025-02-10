defmodule Sanbase.Repo.Migrations.ChangeMetricsArrayType do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("ALTER TABLE chart_configurations ALTER COLUMN metrics TYPE text[];")
    execute("ALTER TABLE chart_configurations ALTER COLUMN metrics SET DEFAULT array[]::text[];")
  end

  def down do
    execute("ALTER TABLE chart_configurations ALTER COLUMN metrics TYPE varchar(255)[];")

    execute("ALTER TABLE chart_configurations ALTER COLUMN metrics SET DEFAULT array[]::varchar[];")
  end
end
