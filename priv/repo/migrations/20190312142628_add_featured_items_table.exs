defmodule Sanbase.Repo.Migrations.AddFeaturedItemsTable do
  use Ecto.Migration

  def change do
    create table(:featured_items) do
      add(:post_id, references(:posts))
      add(:user_list_id, references(:user_lists))
      add(:user_trigger_id, references(:user_triggers))
      timestamps()
    end

    fk_check = """
    (CASE WHEN post_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_list_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN user_trigger_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    create(constraint(:featured_items, :only_one_fk, check: fk_check))
    create(unique_index(:featured_items, [:post_id]))
    create(unique_index(:featured_items, [:user_list_id]))
    create(unique_index(:featured_items, [:user_trigger_id]))
  end
end
