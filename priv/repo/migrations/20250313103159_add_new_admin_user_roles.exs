defmodule :"Elixir.Sanbase.Repo.Migrations.Add-new-admin-user-roles" do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO roles (id, name) VALUES
      (9, 'Admin Panel Viewer'),
      (10, 'Admin Panel Editor'),
      (11, 'Admin Panel Owner')
    """)
  end

  def down do
    execute("""
    DELETE FROM roles WHERE id IN (9, 10, 11)
    """)
  end
end
