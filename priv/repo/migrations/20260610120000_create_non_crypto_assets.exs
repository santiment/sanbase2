defmodule Sanbase.Repo.Migrations.CreateNonCryptoAssets do
  use Ecto.Migration

  def change() do
    create table(:non_crypto_assets) do
      add(:slug, :string, null: false)
      add(:name, :string, null: false)
      add(:ticker, :string)
      add(:asset_type, :string, null: false)
      add(:description, :text)
      add(:logo_url, :string)
      add(:website_link, :string)
      add(:is_hidden, :boolean, default: false, null: false)
      add(:hidden_since, :utc_datetime)
      add(:hidden_reason, :text)
      add(:metadata, :jsonb, default: "{}")

      timestamps()
    end

    # Constrain asset_type at the DB boundary so raw SQL / imports / admin paths
    # cannot drift from the Ecto.Enum contract. Keep in sync with
    # `Sanbase.NonCryptoAsset.asset_types/0`.
    create(
      constraint(:non_crypto_assets, :valid_asset_type,
        check: "asset_type IN ('stock', 'commodity', 'index', 'forex', 'fund', 'bond', 'other')"
      )
    )

    create(unique_index(:non_crypto_assets, [:slug]))
    create(index(:non_crypto_assets, [:asset_type]))
  end
end
