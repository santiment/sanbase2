defmodule Sanbase.Repo.Migrations.CreateDeepResearchSessionsAndTurns do
  use Ecto.Migration

  def change do
    create table(:deep_research_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:title, :text, null: false)
      add(:model_tier, :string, null: false)
      add(:thread_id, :string)
      add(:is_public, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:deep_research_sessions, [:user_id, :updated_at]))

    create table(:deep_research_turns, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :session_id,
        references(:deep_research_sessions, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:position, :integer, null: false)
      add(:question, :text, null: false)
      add(:report, :text)
      add(:error, :text)
      add(:clarification, {:array, :string}, default: [])
      add(:phase, :string, null: false, default: "planning")
      add(:model_tier, :string)
      add(:timeline, {:array, :map}, default: [])
      add(:sources, {:array, :map}, default: [])
      add(:started_at, :utc_datetime_usec, null: false)
      add(:finished_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:deep_research_turns, [:session_id, :position]))

    create(
      constraint(:deep_research_turns, :valid_phase,
        check:
          "phase IN ('idle','planning','researching','writing','awaiting_user','completed','failed','cancelled')"
      )
    )
  end
end
