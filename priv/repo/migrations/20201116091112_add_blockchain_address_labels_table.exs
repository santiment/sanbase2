defmodule Sanbase.Repo.Migrations.AddBlockchainAddressLabelsTable do
  use Ecto.Migration

  @table :blockchain_address_labels

  def change do
    create(table(@table)) do
      add(:label, :string, null: false)
      add(:notes, :string)
    end

    create(unique_index(@table, [:label]))
  end
end
