defmodule Sanbase.Repo.Migrations.AddMoreUserRoles do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO roles (id, name) VALUES
      ((SELECT COALESCE(MAX(id), 0) + 1 FROM roles), 'Santiment WebPanel Viewer'),
      ((SELECT COALESCE(MAX(id), 0) + 2 FROM roles), 'Santiment WebPanel Editor'),
      ((SELECT COALESCE(MAX(id), 0) + 3 FROM roles), 'Santiment WebPanel Admin')
    """)
  end

  def down do
    execute("""
    DELETE FROM roles
    WHERE name IN ('Santiment WebPanel Viewer', 'Santiment WebPanel Editor', 'Santiment WebPanel Admin')
    """)
  end
end
