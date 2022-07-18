defmodule Sanbase.Comment do
  @moduledoc ~s"""
  Comment definition module.

  A comment is represented by its:
  - author
  - content
  - subcomments & subcomments_count
  - parent_id - The id of the comment to which this comment is a direct subcomment.
    The parent of the subcomment in the tree this comment is part of (if not nil)
  - root_parent_id - The top-level comment id in the chain of subcomments.
    The root of the tree this comment is part of (if not nil)
  - timestamp fields


  The EntityComment module is used to interact with comments and is
  invisible to the outside world
  """
  use Ecto.Schema

  import Ecto.{Query, Changeset}
  import Sanbase.Comments.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.ShortUrl
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.BlockchainAddress
  alias Sanbase.Dashboard
  alias Sanbase.UserList
  alias Sanbase.Chart.Configuration, as: ChartConfiguration

  require Sanbase.Utils.Config, as: Config

  @max_comment_length 15_000

  @insights_table "post_comments_mapping"
  @short_urls_table "short_url_comments_mapping"
  @timeline_events_table "timeline_event_comments_mapping"
  @blockchain_addrs_table "blockchain_address_comments_mapping"
  @dashboard_table "dashboard_comments_mapping"
  @watchlists_table "watchlist_comments_mapping"
  @chart_configs_table "chart_configuration_comments_mapping"

  schema "comments" do
    field(:content, :string)
    field(:edited_at, :naive_datetime, default: nil)
    field(:parent_id, :integer)
    field(:root_parent_id, :integer)
    field(:subcomments_count, :integer, default: 0)

    belongs_to(:user, User)
    belongs_to(:parent, __MODULE__, foreign_key: :parent_id, references: :id, define_field: false)

    belongs_to(:root_parent, __MODULE__,
      foreign_key: :id,
      references: :root_parent_id,
      define_field: false
    )

    has_many(:sub_comments, __MODULE__, foreign_key: :parent_id, references: :id)

    # The comment table holds only the conent and the relation of the comment to its
    # parent/root (the hierarchy). The actual entity to which this comment is
    # attached to (an insight, an event, etc) is done via the mapping tables.
    # This way we can easily add new types of comments without having to change
    # the existing code, manipulate the DB schema, etc.
    many_to_many(:insights, Post, join_through: @insights_table)
    many_to_many(:watchlists, UserList, join_through: @watchlists_table)
    many_to_many(:short_urls, ShortUrl, join_through: @short_urls_table)
    many_to_many(:timeline_events, TimelineEvent, join_through: @timeline_events_table)
    many_to_many(:blockchain_addresses, BlockchainAddress, join_through: @blockchain_addrs_table)

    many_to_many(:dashboards, Dashboard.Schema,
      join_keys: [comment_id: :id, dashboard_id: :id],
      join_through: @dashboard_table
    )

    many_to_many(:chart_configurations, ChartConfiguration,
      join_through: @chart_configs_table,
      join_keys: [comment_id: :id, chart_configuration_id: :id]
    )

    timestamps()
  end

  def by_id(id) do
    Repo.get(__MODULE__, id)
  end

  def changeset(%__MODULE__{} = comment, attrs \\ %{}) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    comment
    |> cast(attrs, [:user_id, :parent_id, :root_parent_id, :content, :edited_at])
    |> validate_required([:user_id, :content])
    |> validate_length(:content, min: 2, max: @max_comment_length)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:root_parent_id)
  end

  def can_create?(user_id) do
    limits = %{
      day: Config.get(:creation_limit_day, 50),
      hour: Config.get(:creation_limit_hour, 20),
      minute: Config.get(:creation_limit_minute, 3)
    }

    Sanbase.Ecto.Common.can_create?(__MODULE__, user_id,
      limits: limits,
      entity_singular: "comment",
      entity_plural: "comments"
    )
  end

  def get_subcomments(comment_id, limit) do
    subcomments_tree_query(comment_id)
    |> order_by([c], c.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp subcomments_tree_query(comment_id) do
    from(
      p in __MODULE__,
      where:
        p.parent_id == ^comment_id or
          p.root_parent_id == ^comment_id
    )
  end

  def create_changeset(user_id, content, parent_id \\ nil) do
    changeset(%__MODULE__{}, %{user_id: user_id, content: content, parent_id: parent_id})
  end

  @doc ~s"""
  Create a (top-level) comment.

  When the parent id is nil:
  There is no need to set the parent_id and the root_parent_id - they both should be nil.

  When the parent id is not nil:
  1. In order to properly set the root_parent_id it must be inherited from the parent
  2. Create the new comment
  3. Update the parent's `subcomments_count` field
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

  def create(user_id, content, parent_id) do
    args = %{user_id: user_id, content: content, parent_id: parent_id}

    Ecto.Multi.new()
    |> multi_run(:select_root_parent_id, args)
    |> multi_run(:create_new_comment, args)
    |> multi_run(:update_subcomments_counts, args)
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
        |> emit_event(:update_comment, %{})

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
        |> emit_event(:anonymize_comment, %{})

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  NOTE: This function should be invoked only manually in special cases!
  This is the only function that actually deletes a comment's record and all its
  subcomments.
  As this comment could be part of a bigger subcomment tree, all subcomment counts
  above it are updated
  """
  def delete_subcomment_tree(comment_id, user_id) do
    # Because of the `on_delete: :delete_all` on the `references` this will
    # delete the whole subtree
    # Starting from the root of the whole subcomments tree update every
    # comment's subcomments_count field in that tree
    with {:ok, comment} <- select_comment(comment_id, user_id),
         {:ok, _} <- Repo.delete(comment),
         {:ok, _} <- update_subcomments_counts(comment.root_parent_id) do
      {:ok, comment}
    else
      {:error, error} ->
        {:error, error}
    end
  end

  def update_subcomments_counts(nil), do: {:ok, nil}

  def update_subcomments_counts(root_id) do
    """
    WITH ids AS (
      SELECT id AS comment_id
      FROM comments AS c
      WHERE c.id = $1 OR c.parent_id = $1 OR c.root_parent_id = $1
    ),
    comment_id_count_map AS (
      SELECT comment_id, COUNT(comment_id)
      FROM comments, ids
      WHERE comment_id = parent_id OR comment_id = root_parent_id
      GROUP BY comment_id
    )

    UPDATE comments
    SET subcomments_count = s.count
    FROM (SELECT comment_id, count FROM comment_id_count_map) AS s
    WHERE id = s.comment_id;
    """
    |> Repo.query([root_id])
  end

  defp multi_run(multi, :select_root_parent_id, %{parent_id: parent_id}) do
    multi
    |> Ecto.Multi.run(:select_root_parent_id, fn _repo, _changes ->
      root_parent_id =
        from(c in __MODULE__, where: c.id == ^parent_id, select: c.root_parent_id)
        |> Repo.one()

      {:ok, root_parent_id}
    end)
  end

  # Private functions

  defp multi_run(multi, :create_new_comment, args) do
    %{user_id: user_id, content: content, parent_id: parent_id} = args

    multi
    |> Ecto.Multi.run(
      :create_new_comment,
      fn _repo, %{select_root_parent_id: parent_root_parent_id} ->
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

  defp multi_run(multi, :update_subcomments_counts, _args) do
    multi
    |> Ecto.Multi.run(
      :update_subcomments_count,
      fn _repo, %{create_new_comment: %__MODULE__{root_parent_id: root_id}} ->
        {:ok, _} = update_subcomments_counts(root_id)
        {:ok, "Updated all subcomment counts in the tree"}
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
