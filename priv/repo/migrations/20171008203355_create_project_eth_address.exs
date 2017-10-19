defmodule Sanbase.Repo.Migrations.CreateProjectEthAddress do
  use Ecto.Migration

  def change do
    create table(:project_eth_address) do
      add :address, :string, unique: true
      add :project_id, references(:project, on_delete: :delete_all)
    end

    create index(:project_eth_address, [:project_id])
  end
end
