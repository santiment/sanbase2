defmodule Sanbase.Repo.Migrations.CreateProjectEthAddress do
  use Ecto.Migration

  def change do
    create table(:project_eth_address) do
      add :address, :string, unique: true
      add :project_id, references(:project, type: :serial, on_delete: :nothing)
    end

    create index(:project_eth_address, [:project_id])
  end
end
