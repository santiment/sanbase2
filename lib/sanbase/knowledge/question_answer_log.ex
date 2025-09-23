defmodule Sanbase.Knowledge.QuestionAnswerLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
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

  def by_id(id) do
    Sanbase.Repo.get(__MODULE__, id)
  end

  def list_entries() do
    __MODULE__
    |> order_by(desc: :inserted_at)
    |> preload([:user])
    |> Repo.all()
  end

  def list_entries(page, page_size) when is_integer(page) and is_integer(page_size) do
    page = if page < 1, do: 1, else: page
    offset = (page - 1) * page_size

    __MODULE__
    |> order_by(desc: :inserted_at)
    |> preload([:user])
    |> limit(^page_size)
    |> offset(^offset)
    |> Repo.all()
  end
end
