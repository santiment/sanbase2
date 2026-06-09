defmodule Sanbase.Repo.Migrations.AddRerankerToQuestionAnswerLogs do
  use Ecto.Migration

  def change do
    alter table(:question_answer_logs) do
      add(:reranker, :string)
    end
  end
end
