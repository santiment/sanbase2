defmodule Sanbase.Repo.Migrations.FillQuestionAnswerLogsType do
  use Ecto.Migration

  import Ecto.Query

  def up do
    # All previously existing questions are of the ask_ai type.
    Sanbase.Repo.update_all(from(qe in Sanbase.Knowledge.QuestionAnswerLog),
      set: [question_type: "ask_ai"]
    )
  end

  def down do
    :ok
  end
end
