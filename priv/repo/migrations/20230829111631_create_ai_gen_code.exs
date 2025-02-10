defmodule Sanbase.Repo.Migrations.CreateAiGenCode do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:ai_gen_code) do
      add(:question, :text)
      add(:answer, :text)
      add(:parent_id, references(:ai_gen_code, on_delete: :nothing), null: true)
      add(:program, :text)
      add(:program_result, :text)
      add(:discord_user, :text)
      add(:guild_id, :text)
      add(:guild_name, :text)
      add(:channel_id, :text)
      add(:channel_name, :text)
      add(:elapsed_time, :integer)
      add(:changes, :text)
      add(:is_saved_vs, :boolean, default: false)
      add(:is_from_vs, :boolean, default: false)

      timestamps()
    end
  end
end
