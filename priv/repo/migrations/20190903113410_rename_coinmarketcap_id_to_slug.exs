defmodule Sanbase.Repo.Migrations.RenameCoinmarketcapIdToSlug do
  @moduledoc false
  use Ecto.Migration

  @table "project"
  def up do
    # Create a new column otherwise we'll have fails during deployment
    # Because the first pod will migrate the DB, but the old, still running
    # pods will continue to try to use `coinmarketcap_id`
    alter table(@table) do
      add(:slug, :string)
    end

    execute("UPDATE #{@table} SET slug = coinmarketcap_id")
  end

  def down do
    alter table(@table) do
      remove(:slug)
    end
  end
end
