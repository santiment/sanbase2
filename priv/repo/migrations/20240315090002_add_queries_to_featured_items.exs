defmodule Sanbase.Repo.Migrations.AddQueriesToFeaturedItems do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:featured_items) do
      add(:query_id, references(:queries))
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_list_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN table_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN query_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    drop(constraint(:featured_items, :only_one_fk))
    create(constraint(:featured_items, :only_one_fk, check: fk_check))
    create(unique_index(:featured_items, [:query_id]))
  end

  def down do
    alter table(:featured_items) do
      remove(:query_id)
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_list_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN chart_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN table_configuration_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    # Dropping the column automatically dropped the constraint and the unique index
    create(constraint(:featured_items, :only_one_fk, check: fk_check))
  end
end
