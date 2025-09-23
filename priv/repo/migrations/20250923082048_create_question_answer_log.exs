defmodule Sanbase.Repo.Migrations.CreateQuestionAnswerLog do
  use Ecto.Migration

  def change do
    create(table(:question_answer_logs, primary_key: false)) do
      add(:id, :uuid, primary_key: true)
      add(:question, :text, null: false)
      add(:answer, :text, null: false)
      add(:source, :string, null: false)
      add(:is_successful, :boolean, null: false)
      add(:errors, :text, null: true)

      add(:user_id, references(:users, on_delete: :nilify_all))

      timestamps()
    end
  end
end
