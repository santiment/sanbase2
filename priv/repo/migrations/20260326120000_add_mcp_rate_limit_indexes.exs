defmodule Sanbase.Repo.Migrations.AddMcpRateLimitIndexes do
  use Ecto.Migration

  def change do
    create(index(:mcp_tool_invocations, [:user_id, :inserted_at]))
    create(index(:mcp_tool_invocations, [:user_id, :tool_name, :inserted_at]))
  end
end
