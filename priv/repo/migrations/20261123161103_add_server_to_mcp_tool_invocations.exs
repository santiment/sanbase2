defmodule Sanbase.Repo.Migrations.AddServerToMcpToolInvocations do
  use Ecto.Migration

  def change() do
    alter table(:mcp_tool_invocations) do
      add(:server, :string, size: 32, null: false, default: "mcp")
    end
  end
end
