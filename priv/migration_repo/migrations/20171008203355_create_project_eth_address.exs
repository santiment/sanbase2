defmodule Sanbase.Repo.Migrations.CreateProjectEthAddress do
  use Ecto.Migration

  def change do
    create table(:project_eth_address) do
      add(:address, :string, null: false)
      add(:project_id, references(:project, on_delete: :delete_all))
    end

    create(unique_index(:project_eth_address, [:address]))
    create(index(:project_eth_address, [:project_id]))
  end
end
