defmodule Sanbase.Repo.Migrations.ExtendQuestionAnswerLogs do
  use Ecto.Migration

  def change do
    alter table(:question_answer_logs) do
      add(:question_type, :string)
    end
  end
end
