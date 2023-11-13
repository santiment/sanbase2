defmodule Sanbase.Repo.Migrations.CreatesMenusTable do
  use Ecto.Migration

  def change do
    # Create menus table
    create table(:menus) do
      add(:name, :string)
      add(:description, :string)

      add(:parent_id, references(:menus, on_delete: :delete_all))

      add(:user_id, references(:users, on_delete: :delete_all))

      add(:is_global, :boolean, default: false)

      timestamps()
    end

    create(index(:menus, [:user_id]))

    # Create menu_items table
    create table(:menu_items) do
      add(:parent_id, references(:menus, on_delete: :delete_all))

      add(:query_id, references(:queries, on_delete: :delete_all))
      add(:dashboard_id, references(:dashboards, on_delete: :delete_all))
      add(:menu_id, references(:menus, on_delete: :delete_all))

      add(:position, :integer)

      timestamps()
    end

    fk_check = """
    (CASE WHEN query_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN dashboard_id IS NULL THEN 0 ELSE 1 END) +
    (CASE WHEN menu_id IS NULL THEN 0 ELSE 1 END) = 1
    """

    create(constraint(:menu_items, :only_one_fk, check: fk_check))
  end
end
