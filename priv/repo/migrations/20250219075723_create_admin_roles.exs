defmodule Sanbase.Repo.Migrations.CreateAdminRoles do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO roles (id, name) VALUES
      (4, 'Metric Registry Viewer'),
      (5, 'Metric Registry Change Suggester'),
      (6, 'Metric Registry Change Approver'),
      (7, 'Metric Registry Deployer'),
      (8, 'Metric Registry Owner')
    """)
  end

  def down do
    execute("""
    DELETE FROM roles WHERE id IN (4,5,6,7,8)
    """)
  end
end
