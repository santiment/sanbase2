defmodule Sanbase.Repo.Migrations.AddCascadeDeleteToQuestionnaire do
  @moduledoc false
  use Ecto.Migration

  def up do
    drop(constraint(:questionnaire_questions, :questionnaire_questions_questionnaire_uuid_fkey))

    alter table(:questionnaire_questions) do
      modify(
        :questionnaire_uuid,
        references(:questionnaires,
          column: :uuid,
          type: :uuid,
          null: false,
          on_delete: :delete_all
        )
      )
    end

    drop(constraint(:questionnaire_answers, :questionnaire_answers_question_uuid_fkey))

    alter table(:questionnaire_answers) do
      modify(
        :question_uuid,
        references(:questionnaire_questions,
          column: :uuid,
          type: :uuid,
          null: false,
          on_delete: :delete_all
        )
      )
    end
  end

  def down do
    :ok
  end
end
