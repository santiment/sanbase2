defmodule Sanbase.Repo.Migrations.AddBlockchainAddressLabelsTable do
  @moduledoc false
  use Ecto.Migration

  @table :blockchain_address_labels

  def change do
    create(table(@table)) do
      add(:name, :string, null: false)
      add(:notes, :string)
    end

    create(unique_index(@table, [:name]))
  end
end
