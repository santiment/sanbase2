defmodule Sanbase.Repo.Migrations.AddNonCryptoAssetToSourceSlugMappings do
  use Ecto.Migration

  @table "source_slug_mappings"

  def change() do
    alter table(@table) do
      add(:non_crypto_asset_id, references(:non_crypto_assets, on_delete: :delete_all))
    end

    create(
      constraint(@table, :exactly_one_asset_reference,
        check: "(project_id IS NULL) <> (non_crypto_asset_id IS NULL)"
      )
    )

    create(
      unique_index(@table, [:source, :non_crypto_asset_id],
        name: :one_mapping_per_source_non_crypto_asset
      )
    )
  end
end
