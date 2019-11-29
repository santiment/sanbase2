defmodule Sanbase.Insight.Comment do
  @moduledoc ~s"""

  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Auth.User

  @max_comment_length 15_000

  schema "comments" do
    field(:content, :string)

    belongs_to(:user, User)
    belongs_to(:parent, __MODULE__)

    has_many(:sub_comments, __MODULE__)

    timestamps()
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def changeset(%__MODULE__{} = comment, attrs \\ %{}) do
    comment
    |> cast(attrs, [:user_id, :content, :parent_id])
    |> validate_length(:content, min: 2, max: @max_comment_length)
    |> foreign_key_constraint(:parent_id)
  end

  def create_changeset(user_id, content, parent_id \\ nil) do
    changeset(%__MODULE__{}, %{user_id: user_id, content: content, parent_id: parent_id})
  end

  def create(user_id, content, parent_id \\ nil) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, content: content, parent_id: parent_id})
    |> Repo.insert()
  end

  def update(comment_id, user_id, content) do
    case select_comment(comment_id, user_id) do
      {:ok, comment} ->
        comment
        |> changeset(%{content: content})
        |> Repo.update()

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Anonymze the comment by changing its author to the anonymous user and the content
  to a default text. This is done so the tree structure is not broken.
  """
  def delete(comment_id, user_id) do
    case select_comment(comment_id, user_id) do
      {:ok, comment} ->
        anonymize(comment)

      {:error, error} ->
        {:error, error}
    end
  end

  defp anonymize(%__MODULE__{} = comment) do
    comment
    |> changeset(%{user_id: User.anonymous_user_id(), content: "The comment has been deleted."})
    |> Repo.update()
  end

  defp select_comment(comment_id, user_id) do
    by_id(comment_id)
    |> case do
      nil ->
        {:error, "Comment with id #{comment_id} is not existing."}

      %__MODULE__{user_id: another_user_id} when another_user_id != user_id ->
        {:error, "Comment with id #{comment_id} is owned by another user."}

      %__MODULE__{user_id: ^user_id} = comment ->
        {:ok, comment}
    end
  end
end
