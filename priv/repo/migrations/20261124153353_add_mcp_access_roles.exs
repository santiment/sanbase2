defmodule Sanbase.Repo.Migrations.AddMcpAccessRoles do
  use Ecto.Migration

  def up() do
    execute("""
    INSERT INTO roles (id, name) VALUES
      (12, 'Knowledge MCP User'),
      (13, 'Dev MCP User')
    ON CONFLICT (id) DO NOTHING
    """)
  end

  def down() do
    execute("DELETE FROM user_roles WHERE role_id IN (12, 13)")
    execute("DELETE FROM roles WHERE id IN (12, 13)")
  end
end
