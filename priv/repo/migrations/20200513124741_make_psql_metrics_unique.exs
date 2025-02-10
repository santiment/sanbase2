defmodule Sanbase.Repo.Migrations.MakePsqlMetricsUnique do
  @moduledoc false
  use Ecto.Migration

  def change do
    create(unique_index(:metrics, [:name]))
  end
end
