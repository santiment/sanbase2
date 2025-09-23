defmodule Sanbase.Knowledge.QuestionAnswerLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "question_answer_logs" do
    field(:question, :string)
    field(:answer, :string)
    field(:source, :string)
    field(:is_successful, :boolean)
    field(:errors, :string)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps()
  end

  @doc false
  def changeset(question_answer_log, attrs) do
    question_answer_log
    |> cast(attrs, [:question, :answer, :source, :user_id, :is_successful, :errors])
    |> validate_required([:question, :answer, :is_successful, :source])
  end

  def create(args) do
    %__MODULE__{}
    |> changeset(args)
    |> Sanbase.Repo.insert()
  end
end
