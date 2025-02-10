defmodule Sanbase.Repo.Migrations.AddBlockchainAddressesTable do
  @moduledoc false
  use Ecto.Migration

  @table :blockchain_addresses
  def change do
    create table(@table) do
      add(:address, :string, null: false)
      add(:infrastructure_id, references(:infrastructures), null: true)
      add(:notes, :text, null: true)
    end

    create(unique_index(@table, [:address, :infrastructure_id]))
  end
end
