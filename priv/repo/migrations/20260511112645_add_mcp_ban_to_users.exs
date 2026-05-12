defmodule Sanbase.Repo.Migrations.AddMcpBanToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:is_mcp_banned, :boolean, null: false, default: false)
      add(:mcp_banned_at, :utc_datetime)
      add(:mcp_banned_reason, :text)
    end

    create(index(:users, [:is_mcp_banned], where: "is_mcp_banned = true"))
  end
end
