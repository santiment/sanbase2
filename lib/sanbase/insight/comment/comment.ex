defmodule Sanbase.Insight.Comment do
  @moduledoc ~s"""

  """
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo
  alias Sanbase.Auth.User

  @max_comment_length 15_000

  schema "comments" do
    field(:content, :string)
    field(:edited_at, :naive_datetime, default: nil)

    belongs_to(:user, User)
    belongs_to(:parent, __MODULE__)

    has_many(:sub_comments, __MODULE__)
    field(:subcomments_count, :integer, default: 0)

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

  def create(user_id, content, nil) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, content: content})
    |> Repo.insert()
  end

  def create(user_id, content, parent_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :create_new,
      %__MODULE__{}
      |> changeset(%{user_id: user_id, content: content, parent_id: parent_id})
    )
    |> Ecto.Multi.run(
      :update_subcomments_count,
      fn _ ->
        from(c in __MODULE__, update: [inc: [subcomments_count: 1]], where: c.id == ^parent_id)
        |> Repo.update_all([])
        |> case do
          {1, _} -> {:ok, "updated the subcomments count of comment #{parent_id}"}
          {:error, error} -> {:error, error}
        end
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{create_new: comment}} ->
        {:ok, comment}

      {:error, _name, error, _} ->
        {:error, error}
    end
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
