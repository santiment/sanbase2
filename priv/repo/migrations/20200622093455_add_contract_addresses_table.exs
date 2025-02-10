defmodule Sanbase.Repo.Migrations.AddContractAddressesTable do
  @moduledoc false
  use Ecto.Migration

  @table "contract_addresses"
  def change do
    create table(@table) do
      add(:address, :string, null: false)
      add(:decimals, :integer, default: 0)
      add(:label, :string)
      add(:description, :text)
      add(:project_id, references(:project))

      timestamps()
    end

    create(unique_index(@table, [:project_id, :address]))
  end
end
