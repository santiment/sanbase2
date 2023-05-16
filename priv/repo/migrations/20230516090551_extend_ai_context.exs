defmodule Sanbase.Repo.Migrations.ExtendAiContext do
  use Ecto.Migration

  def change do
    alter table(:ai_context) do
      add(:guild_id, :string)
      add(:guild_name, :string)
      add(:channel_id, :string)
      add(:channel_name, :string)
      add(:elapsed_time, :float)
      add(:tokens_request, :integer)
      add(:tokens_response, :integer)
      add(:tokens_total, :integer)
      add(:error_message, :string)
      add(:total_cost, :float)
      add(:command, :string)
    end
  end
end
