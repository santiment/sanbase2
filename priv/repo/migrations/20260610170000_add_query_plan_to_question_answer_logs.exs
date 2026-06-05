defmodule Sanbase.Repo.Migrations.AddQueryPlanToQuestionAnswerLogs do
  use Ecto.Migration

  def change do
    alter table(:question_answer_logs) do
      # The resolved Sanbase.Knowledge.QueryPlan as JSON (see QueryPlan.to_map/1)
      add(:query_plan, :map)
    end
  end
end
