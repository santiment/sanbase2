defmodule Sanbase.Repo.Migrations.ExtendMcpToolInvocations do
  use Ecto.Migration

  def change do
    alter table(:mcp_tool_invocations) do
      add(:user_agent, :string, size: 512)
      add(:client, :string, size: 32)
      add(:session_id, :string, size: 128)
      add(:kind, :string, null: false, default: "tool")
    end

    create(index(:mcp_tool_invocations, [:session_id]))
    create(index(:mcp_tool_invocations, [:client]))
    create(index(:mcp_tool_invocations, [:client, :inserted_at]))
    create(index(:mcp_tool_invocations, [:kind, :inserted_at]))
  end
end
