defmodule Sanbase.Repo.Migrations.CreateAssetExchangeTable do
  @moduledoc false
  use Ecto.Migration

  @table :asset_exchange_pairs
  def change do
    create table(@table) do
      add(:base_asset, :string, null: false)
      add(:quote_asset, :string, null: false)
      add(:exchange, :string, null: false)
      add(:source, :string, null: false)
      add(:last_update, :utc_datetime)

      timestamps()
    end

    create(index(@table, [:base_asset]))
    create(index(@table, [:exchange]))
    create(unique_index(@table, [:base_asset, :quote_asset, :exchange, :source]))
  end
end
