defmodule Sanbase.Repo.Migrations.AddVotesAiContext do
  use Ecto.Migration

  def change do
    alter table(:ai_context) do
      add(:thread_id, :string)
      add(:thread_name, :string)
      add(:votes, :jsonb, default: "{}")
    end
  end
end
