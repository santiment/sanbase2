defmodule Sanbase.Questionnaire.Question do
  @moduledoc ~s"""
  Questionnaire question implementation.

  A questionnaire consists of one or more questions.
  The question consists of:
    - The questionnaire id it belongs to
    - The position in the questionnaire (first, second, etc. question)
    - The question text and type
    - The answer options
    - Date & time related fields
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Questionnaire
  alias Sanbase.Questionnaire.Validation

  # UUID V4
  @type question_uuid :: String.t()
  @type questionnaire_uuid :: String.t()

  @type t :: %__MODULE__{
          questionnaire_uuid: String.t(),
          order: non_neg_integer(),
          question: String.t(),
          type: :single_select | :multi_select | :open_text | :open_number | :boolean,
          answer_options: Map.t(),
          has_extra_open_text_answer: boolean(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @foreign_key_type :binary_id
  @primary_key {:uuid, :binary_id, autogenerate: true}
  schema "questionnaire_questions" do
    belongs_to(:questionnaire, Questionnaire,
      type: :binary_id,
      references: :uuid,
      foreign_key: :questionnaire_uuid
    )

    field(:order, :integer)
    field(:question, :string)
    field(:type, QuestionType, default: :single_select)
    field(:answer_options, :map, default: %{})

    # If true, append an open text answer at the end.
    field(:has_extra_open_text_answer, :boolean, default: false)

    timestamps()
  end

  @fields [
    :questionnaire_uuid,
    :order,
    :question,
    :type,
    :answer_options,
    :has_extra_open_text_answer
  ]
  @update_fields @fields -- [:questionnaire_uuid]

  @doc ~s"""
  Get a question by the UUID V4 id
  """
  @spec by_uuid(question_uuid, Keyword.t()) :: {:ok, t()} | {:error, String.t()}
  def by_uuid(id, _opts \\ []) do
    case Sanbase.Repo.get(__MODULE__, id) do
      nil -> {:error, "No questionnaire question with id #{id} exists"}
      %__MODULE__{} = question -> {:ok, question}
    end
  end

  @doc ~s"""
  Create a new question that belongs to a given questionnaire
  """
  @spec create(questionnaire_uuid, Map.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(questionnaire_uuid, %{} = params) do
    type = params[:type]

    params = Map.put(params, :questionnaire_uuid, questionnaire_uuid)

    %__MODULE__{}
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> validate_change(:answer_options, &validate_answer_options(&1, &2, type))
    |> validate_change(:question, &validate_question(&1, &2, type))
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Update existing question
  """
  @spec update(question_uuid, Map.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(id, %{} = params) do
    case by_uuid(id) do
      {:ok, %__MODULE__{} = question} ->
        type = params[:type] || question.type

        question
        |> cast(params, @update_fields)
        |> validate_required(@update_fields)
        |> validate_change(:answer_options, &validate_answer_options(&1, &2, type))
        |> validate_change(:question, &validate_question(&1, &2, type))
        |> Sanbase.Repo.update()

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Delete an existing question
  """
  @spec delete(question_uuid) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(uuid) do
    case by_uuid(uuid) do
      {:ok, %__MODULE__{} = question} -> Sanbase.Repo.delete(question)
      {:error, error} -> {:error, error}
    end
  end

  @doc ~s"""

  """
  @spec get_type(question_uuid) :: {:ok, Atom.t()} | {:error, Ecto.Changeset.t()}
  def get_type(question_uuid) do
    case by_uuid(question_uuid) do
      {:ok, %__MODULE__{} = question} -> {:ok, question.type}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp validate_question(:question, question, question_type) do
    case Validation.validate_question_text(question_type, question) do
      true -> []
      {:error, error} -> [question: error]
    end
  end

  defp validate_answer_options(:answer_options, answer_options, question_type) do
    case Validation.validate_question_answers_options(question_type, answer_options) do
      true -> []
      {:error, error} -> [answer_options: error]
    end
  end
end
