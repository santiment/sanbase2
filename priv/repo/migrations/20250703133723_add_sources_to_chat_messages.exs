defmodule Sanbase.Repo.Migrations.AddSourcesToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add(:sources, {:array, :map}, default: [])
    end

    create(index(:chat_messages, [:sources], using: :gin))
  end
end
