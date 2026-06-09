defmodule Sanbase.Repo.Migrations.AddContextExpansionToQuestionAnswerLogs do
  use Ecto.Migration

  def change do
    alter table(:question_answer_logs) do
      add(:context_expansion, :boolean, default: false, null: false)
    end
  end
end
