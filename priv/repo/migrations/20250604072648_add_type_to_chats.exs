defmodule Sanbase.Repo.Migrations.AddTypeToChats do
  use Ecto.Migration

  def change do
    alter table(:chats) do
      add(:type, :string, null: false, default: "dyor_dashboard")
    end

    create(index(:chats, [:type]))
  end
end
