defmodule Sanbase.Repo.Migrations.CreateChartConfigurations do
  @moduledoc false
  use Ecto.Migration

  @table :chart_configurations
  def change do
    create table(@table) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:project_id, references(:project, on_delete: :delete_all))

      add(:title, :string)
      add(:description, :text)
      add(:is_public, :boolean, default: false)

      add(:metrics, {:array, :string}, default: [])
      add(:anomalies, {:array, :string}, default: [])

      timestamps()
    end

    create(index(@table, [:user_id]))
    create(index(@table, [:project_id]))
  end
end
