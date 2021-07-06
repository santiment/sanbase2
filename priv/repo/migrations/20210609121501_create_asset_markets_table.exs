defmodule Sanbase.Repo.Migrations.CreateAssetMarketsTable do
  use Ecto.Migration

  def change do
    create table(:asset_exchange_pairs) do
      add(:base_asset, :string, null: false)
      add(:quote_asset, :string, null: false)
      add(:exchange, :string, null: false)
      add(:source, :string, null: false)
      add(:last_update, :utc_datetime)

      timestamps()
    end
  end
end
