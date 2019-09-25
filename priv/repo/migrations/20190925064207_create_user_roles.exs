defmodule Sanbase.Repo.Migrations.CreateUserRoles do
  use Ecto.Migration

  def up do
    create table(:roles) do
      add(:name, :string, null: false)
      add(:code, :string, null: false)
    end

    create(unique_index(:roles, [:code]))

    create table(:user_roles, primary_key: false) do
      add(:user_id, references(:users), null: false, on_delete: :delete_all, primary_key: true)
      add(:role_id, references(:roles), null: false, on_delete: :delete_all, primary_key: true)

      timestamps()
    end

    create(unique_index(:user_roles, [:user_id, :role_id]))

    execute("""
    INSERT INTO roles (id, name, code) VALUES
      (1, 'Santiment Team Member', 'san_team'),
      (2, 'Santiment Family Member', 'san_family')
    """)
  end

  def down do
    drop(table(:user_roles))
    drop(table(:roles))
  end
end
