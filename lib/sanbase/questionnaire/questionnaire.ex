defmodule Sanbase.Questionnaire do
  @moduledoc ~s"""
  In-house questionnaire implementation.

  The Questionnaire is a way of recording questions and their registered users
  answers.

  Doing the questionnaire in-house instead of using available tools allows for:
  - More flexibility
  - No added cost for avoiding limits (number of responses, duration, etc.)
  - Ease of acting upon the answers (make some feature avaialble if the questionnaire is filled)
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias __MODULE__.Question
  alias __MODULE__.Answer

  @type questionnaire_uuid :: String.t()
  @type t :: %__MODULE__{
          uuid: String.t(),
          name: String.t(),
          description: String.t(),
          questions: list(),
          ends_at: DateTime.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @primary_key {:uuid, :binary_id, autogenerate: true}
  schema "questionnaires" do
    field(:name, :string)
    field(:description, :string)
    field(:is_deleted, :boolean, default: false)
    has_many(:questions, Question, references: :uuid)

    field(:ends_at, :utc_datetime)

    timestamps()
  end

  @doc ~s"""
  Get a questionnaire and the questions it contains
  """
  @spec by_uuid(questionnaire_uuid) :: {:ok, t()} | {:error, String.t()}
  def by_uuid(questionnaire_uuid) do
    query =
      from(q in __MODULE__,
        where: q.uuid == ^questionnaire_uuid and q.is_deleted != true,
        preload: [:questions]
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = questionnaire ->
        {:ok, questionnaire}

      nil ->
        {:error, "Questionnaire with uuid #{questionnaire_uuid} does not exist"}
    end
  end

  @doc ~s"""
  Create a new empty questionnaire.
  """
  @spec create(map) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    %__MODULE__{}
    |> cast(params, [:name, :description, :ends_at])
    |> validate_required([:name, :description])
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Update an existing questionnaire.
  """
  @spec update(questionnaire_uuid, map) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(questionnaire_uuid, params) do
    case by_uuid(questionnaire_uuid) do
      {:ok, %__MODULE__{} = questionnaire} ->
        questionnaire
        |> cast(params, [:name, :description, :ends_at])
        |> Sanbase.Repo.update()

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Delete an existing questionnaire
  """
  @spec delete(questionnaire_uuid) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(questionnaire_uuid) do
    case by_uuid(questionnaire_uuid) do
      {:ok, %__MODULE__{} = questionnaire} ->
        Sanbase.Repo.delete(questionnaire)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Add a question to an existing quesionnaire
  """
  def create_question(questionnaire_uuid, params),
    do: Question.create(questionnaire_uuid, params)

  @doc ~s"""
  Update an existing question
  """
  def update_question(question_uuid, params),
    do: Question.update(question_uuid, params)

  @doc ~s"""
  Update an existing question
  """
  def delete_question(question_uuid),
    do: Question.delete(question_uuid)

  @doc ~s"""
  Create an answer to a given question
  """
  def create_answer(question_uuid, user_id, params),
    do: Answer.create(question_uuid, user_id, params)

  @doc ~s"""
  """
  def update_answer(answer_uuid, user_id, params),
    do: Answer.update(answer_uuid, user_id, params)

  @doc ~s"""
  """
  def delete_answer(answer_uuid, user_id),
    do: Answer.delete(answer_uuid, user_id)

  def user_answers(questionnaire_uuid, user_id),
    do: Answer.user_answers(questionnaire_uuid, user_id)
end
