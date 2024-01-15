defmodule Sanbase.Repo.Migrations.ExtendThreadAiContext do
  use Ecto.Migration

  def change do
    alter table(:thread_ai_context) do
      add(:elapsed_time, :float)
      add(:tokens_request, :integer)
      add(:tokens_response, :integer)
      add(:tokens_total, :integer)
      add(:error_message, :string)
      add(:total_cost, :float)

      modify(:channel_id, :string)
      modify(:guild_id, :string)
      modify(:thread_id, :string)
    end
  end
end
