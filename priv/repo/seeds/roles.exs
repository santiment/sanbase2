# Run with: mix run priv/repo/seeds/roles.exs
#
# Roles. Production has them from migrations, which do not run on a database
# loaded from structure.sql.
Sanbase.Seeds.LocalOnly.ensure!()

alias Sanbase.Accounts.Role

roles = [
  {Role.san_team_role_id(), "Santiment Team Member"},
  {Role.san_family_role_id(), "Santiment Family Member"},
  {Role.san_moderator_role_id(), "Santiment Moderator"},
  {Role.metric_registry_viewer_role_id(), "Metric Registry Viewer"},
  {Role.metric_registry_change_suggester_role_id(), "Metric Registry Change Suggester"},
  {Role.metric_registry_change_approver_role_id(), "Metric Registry Change Approver"},
  {Role.metric_registry_deployer_role_id(), "Metric Registry Deployer"},
  {Role.metric_registry_owner_role_id(), "Metric Registry Owner"},
  {Role.admin_panel_viewer_role_id(), "Admin Panel Viewer"},
  {Role.admin_panel_editor_role_id(), "Admin Panel Editor"},
  {Role.admin_panel_owner_role_id(), "Admin Panel Owner"},
  {Role.mcp_knowledge_access_role_id(), "Knowledge MCP User"},
  {Role.mcp_dev_access_role_id(), "Dev MCP User"}
]

rows = Enum.map(roles, fn {id, name} -> %{id: id, name: name} end)
Sanbase.Repo.insert_all(Role, rows, on_conflict: :nothing)
