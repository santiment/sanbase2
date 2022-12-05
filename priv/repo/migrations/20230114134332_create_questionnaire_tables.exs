defmodule Sanbase.Repo.Migrations.CreateQuestionnaireTables do
  use Ecto.Migration

  def change do
    create table(:questionnaires, primary_key: false) do
      add(:uuid, :uuid, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)

      add(:ends_at, :utc_datetime)

      timestamps()
    end

    create table(:questionnaire_questions, primary_key: false) do
      add(:uuid, :uuid, primary_key: true)

      add(:questionnaire_uuid, references(:questionnaires, column: :uuid, type: :uuid))

      add(:order, :integer, null: false)
      add(:question, :string, null: false)
      add(:type, :question_type, default: "open_text", null: false)
      add(:answer_options, :map, default: "{}", null: false)

      # If true, append an open text answer at the end.
      add(:has_extra_open_text_answer, :boolean, default: false, null: false)

      timestamps()
    end

    create table(:questionnaire_answers, primary_key: false) do
      add(:uuid, :uuid, primary_key: true)
      add(:user_id, references(:users), null: false)

      add(:question_uuid, references(:questionnaire_questions, column: :uuid, type: :uuid),
        null: false
      )

      add(:answer, :jsonb, null: false)

      timestamps()
    end

    create(unique_index(:questionnaire_answers, [:question_uuid, :user_id]))
  end
end
