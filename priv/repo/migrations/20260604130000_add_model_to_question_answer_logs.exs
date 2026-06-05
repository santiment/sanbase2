defmodule Sanbase.Repo.Migrations.AddModelToQuestionAnswerLogs do
  use Ecto.Migration

  def change do
    alter table(:question_answer_logs) do
      add(:model, :string)
    end
  end
end
