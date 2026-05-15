defmodule Sanbase.Repo.Migrations.AddPlanSnapshotToMcpToolInvocations do
  use Ecto.Migration

  def change do
    alter table(:mcp_tool_invocations) do
      add(:product_code, :string, size: 16)
      add(:plan_name, :string, size: 32)
    end

    create(index(:mcp_tool_invocations, [:plan_name, :inserted_at]))
    create(index(:mcp_tool_invocations, [:product_code, :inserted_at]))
  end
end
