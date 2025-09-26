defmodule Sanbase.Knowledge.QuestionAnswerLog do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "question_answer_logs" do
    field(:question, :string)
    field(:answer, :string)
    field(:source, :string)
    field(:is_successful, :boolean)
    field(:errors, :string)
    field(:question_type, :string)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps()
  end

  @doc false
  def changeset(question_answer_log, attrs) do
    question_answer_log
    |> cast(attrs, [
      :question,
      :answer,
      :source,
      :user_id,
      :is_successful,
      :errors,
      :question_type
    ])
    |> validate_required([:question, :answer, :is_successful, :source, :question_type])
    |> validate_inclusion(:question_type, ["ask_ai", "smart_search"])
  end

  def create(args) do
    %__MODULE__{}
    |> changeset(args)
    |> Sanbase.Repo.insert()
  end

  def by_id(id) do
    query = from(log in __MODULE__, where: log.id == ^id, preload: [:user])

    case Sanbase.Repo.one(query) do
      nil -> {:error, "No entry with id #{id} found"}
      entry -> {:ok, entry}
    end
  end

  def list_entries() do
    __MODULE__
    |> order_by(desc: :inserted_at)
    |> preload([:user])
    |> Sanbase.Repo.all()
  end

  def list_entries(page, page_size) when is_integer(page) and is_integer(page_size) do
    page = if page < 1, do: 1, else: page
    offset = (page - 1) * page_size

    __MODULE__
    |> order_by(desc: :inserted_at)
    |> preload([:user])
    |> limit(^page_size)
    |> offset(^offset)
    |> Sanbase.Repo.all()
  end
end
