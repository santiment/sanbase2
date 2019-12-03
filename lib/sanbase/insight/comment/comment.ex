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
    belongs_to(:root_parent, __MODULE__)

    has_many(:sub_comments, __MODULE__)
    field(:subcomments_count, :integer, default: 0)

    timestamps()
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def changeset(%__MODULE__{} = comment, attrs \\ %{}) do
    comment
    |> cast(attrs, [:user_id, :content, :parent_id, :root_parent_id, :edited_at])
    |> validate_length(:content, min: 2, max: @max_comment_length)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:root_parent_id)
  end

  def create_changeset(user_id, content, parent_id \\ nil) do
    changeset(%__MODULE__{}, %{user_id: user_id, content: content, parent_id: parent_id})
  end

  @doc ~s"""
  Createa a (top-level) comment. When the parent id is nil there is no need to set
  the parent_id and the root_parent_id - they both should be nil.
  """
  @spec create(
          user_id :: non_neg_integer(),
          content :: String.t(),
          parent_id :: nil | non_neg_integer()
        ) ::
          {:ok, %__MODULE__{}} | {:error, String.t()}
  def create(user_id, content, nil) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, content: content})
    |> Repo.insert()
  end

  @doc ~s"""
  Create a subcomment. A subcomment is created by a transaction with 3 steps:
    1. In order to properly set the root_parent_id it must be inherited from the parent
    2. Create the new comment
    3. Update the parent's `subcomments_count` field
  """
  def create(user_id, content, parent_id) do
    args = %{user_id: user_id, content: content, parent_id: parent_id}

    Ecto.Multi.new()
    |> multi_run(:select_root_parent_id, args)
    |> multi_run(:create_new_comment, args)
    |> multi_run(:update_parent_subcomments_count, args)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_new_comment: comment}} ->
        {:ok, comment}

      {:error, _name, error, _} ->
        {:error, error}
    end
  end

  def update(comment_id, user_id, content) do
    case select_comment(comment_id, user_id) do
      {:ok, comment} ->
        comment
        |> changeset(%{content: content, edited_at: NaiveDateTime.utc_now()})
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

  defp multi_run(multi, :select_root_parent_id, %{parent_id: parent_id}) do
    multi
    |> Ecto.Multi.run(:select_root_parent_id, fn _ ->
      parent_ids =
        from(c in __MODULE__, where: c.id == ^parent_id, select: c.root_parent_id)
        |> Repo.one()

      {:ok, parent_ids}
    end)
  end

  # Private functions

  defp multi_run(multi, :create_new_comment, args) do
    %{user_id: user_id, content: content, parent_id: parent_id} = args

    multi
    |> Ecto.Multi.run(
      :create_new_comment,
      fn %{select_root_parent_id: parent_root_parent_id} ->
        # Handle all case: If the parent has a parent_root_id - inherit it
        # If the parent does not have it - then the parent is a top level comment
        # and the current parent_root_id should be se to parent_id
        root_parent_id = parent_root_parent_id || parent_id

        %__MODULE__{}
        |> changeset(%{
          user_id: user_id,
          content: content,
          parent_id: parent_id,
          root_parent_id: root_parent_id
        })
        |> Repo.insert()
      end
    )
  end

  defp multi_run(multi, :update_parent_subcomments_count, %{parent_id: parent_id}) do
    multi
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
