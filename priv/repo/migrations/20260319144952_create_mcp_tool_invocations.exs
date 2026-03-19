defmodule Sanbase.Repo.Migrations.CreateMcpToolInvocations do
  use Ecto.Migration

  def change do
    create table(:mcp_tool_invocations) do
      add(:user_id, references(:users, on_delete: :nilify_all), null: true)
      add(:tool_name, :string, null: false)
      add(:params, :map, default: %{})
      add(:metrics, {:array, :string}, default: [])
      add(:slugs, {:array, :string}, default: [])
      add(:response_size_bytes, :integer)
      add(:is_successful, :boolean, null: false)
      add(:error_message, :text)
      add(:duration_ms, :integer, null: false)
      add(:auth_method, :string)

      timestamps()
    end

    create(index(:mcp_tool_invocations, [:user_id]))
    create(index(:mcp_tool_invocations, [:tool_name]))
    create(index(:mcp_tool_invocations, [:inserted_at]))

    execute(
      "CREATE INDEX mcp_tool_invocations_metrics_gin ON mcp_tool_invocations USING gin (metrics)",
      "DROP INDEX mcp_tool_invocations_metrics_gin"
    )
  end
end
