defmodule Sanbase.Repo.Migrations.AddNonCryptoAssetToSourceSlugMappings do
  use Ecto.Migration

  @table "source_slug_mappings"

  def up() do
    alter table(@table) do
      add(:non_crypto_asset_id, references(:non_crypto_assets, on_delete: :delete_all))
    end

    # project_id has been nullable since the table was created; rows without a
    # project carry no information and would violate the check constraint below
    #
    # also prod database has been manually checked and no such rows exist.
    # Log how many rows are removed for an audit trail, then delete them.
    execute("""
    DO $$
    BEGIN
      RAISE NOTICE 'Deleting % orphaned #{@table} rows with NULL project_id',
        (SELECT count(*) FROM #{@table} WHERE project_id IS NULL);
    END $$
    """)

    execute("DELETE FROM #{@table} WHERE project_id IS NULL")

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

  def down() do
    drop(constraint(@table, :exactly_one_asset_reference))

    alter table(@table) do
      remove(:non_crypto_asset_id)
    end
  end
end
