defmodule Sanbase.Repo.Migrations.AddSanModeratorRole do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO roles (id, name) VALUES
      (3, 'Santiment Moderator')
    """)
  end

  def down do
    execute("""
    DELETE FROM roles WHERE id = 3
    """)
  end
end
