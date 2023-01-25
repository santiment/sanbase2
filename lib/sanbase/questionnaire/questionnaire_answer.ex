defmodule Sanbase.Questionnaire.Answer do
  @moduledoc ~s"""
  Questionnaire answer implementation

  An answer is the answer given by a user to a specific question.
  """

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Questionnaire.Question
  alias Sanbase.Questionnaire.Validation

  # UUID v4
  @type questionnaire_uuid :: String.t()
  @type answer_uuid :: String.t()
  @type question_uuid :: String.t()
  @type user_id :: non_neg_integer()

  @type t :: %__MODULE__{
          uuid: String.t(),
          question_uuid: String.t(),
          user_id: non_neg_integer(),
          answer: Map.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @primary_key {:uuid, :binary_id, autogenerate: true}
  schema "questionnaire_answers" do
    belongs_to(:question, Question,
      type: :binary_id,
      references: :uuid,
      foreign_key: :question_uuid
    )

    belongs_to(:user, User)

    field(:answer, :map)

    timestamps()
  end

  @fields [:question_uuid, :user_id, :answer]

  @doc ~s"""
  Record the answer of a user to a question.
  """
  @spec create(question_uuid, non_neg_integer, Map.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(question_uuid, user_id, params) do
    {:ok, type} = Question.get_type(question_uuid)

    params = params |> Map.merge(%{question_uuid: question_uuid, user_id: user_id})

    %__MODULE__{}
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> validate_change(:answer, &validate_answer(&1, &2, type))
    |> Sanbase.Repo.insert(
      on_conflict: {:replace_all_except, [:uuid]},
      conflict_target: [:question_uuid, :user_id],
      returning: true
    )
  end

  @doc ~s"""
  Update an answer
  """
  @spec update(answer_uuid, non_neg_integer(), Map.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(uuid, user_id, params) do
    case Sanbase.Repo.get(__MODULE__, uuid) do
      %__MODULE__{user_id: ^user_id} = answer ->
        answer
        |> cast(params, @fields -- [:user_id])
        |> Sanbase.Repo.update()

      _ ->
        {:error, "Anaswer with uuid #{uuid} does not exist or is owned by another user"}
    end
  end

  @doc ~s"""
  Delete an answer
  """
  @spec delete(answer_uuid, non_neg_integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(uuid, user_id) do
    case Sanbase.Repo.get(__MODULE__, uuid) do
      %__MODULE__{user_id: ^user_id} = answer ->
        Sanbase.Repo.delete(answer)

      _ ->
        {:error, "Anaswer with uuid #{uuid} does not exist or it is owned by another user"}
    end
  end

  @doc ~s"""
  Get a list of a given user's answers for a questionnaire
  """
  @spec user_answers(questionnaire_uuid, non_neg_integer) :: {:ok, list(t())}
  def user_answers(questionnaire_uuid, user_id) do
    question_uuids =
      from(q in Question,
        where: q.questionnaire_uuid == ^questionnaire_uuid,
        select: q.uuid
      )

    query =
      from(
        ans in __MODULE__,
        where:
          ans.question_uuid in subquery(question_uuids) and
            ans.user_id == ^user_id,
        preload: [:question]
      )

    {:ok, Sanbase.Repo.all(query)}
  end

  # Private functions

  defp validate_answer(:answer, answer, type) do
    case Validation.validate_user_provided_answer(answer, type) do
      true -> []
      {:error, error} -> [answer: error]
    end
  end
end
