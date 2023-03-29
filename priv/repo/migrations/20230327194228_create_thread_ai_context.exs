defmodule Sanbase.Repo.Migrations.CreateThreadAiContext do
  use Ecto.Migration

  def change do
    create table(:thread_ai_context) do
      add(:discord_user, :string)
      add(:guild_id, :bigint)
      add(:guild_name, :string)
      add(:channel_id, :bigint)
      add(:channel_name, :string)
      add(:thread_id, :bigint)
      add(:thread_name, :string)
      add(:question, :text)
      add(:answer, :text)
      add(:votes_pos, :integer, default: 0)
      add(:votes_neg, :integer, default: 0)

      timestamps()
    end
  end
end
