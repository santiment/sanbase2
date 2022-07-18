defmodule Sanbase.Comments.EntityComment do
  @moduledoc """
  Module for dealing with comments for certain entities.
  """
  import Ecto.Query
  import Sanbase.Comments.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Repo
  alias Sanbase.Comment

  alias Sanbase.Comment.{
    BlockchainAddressComment,
    ChartConfigurationComment,
    DashboardComment,
    PostComment,
    ShortUrlComment,
    TimelineEventComment,
    WalletHuntersProposalComment,
    WatchlistComment
  }

  @type comment_struct ::
          %BlockchainAddressComment{}
          | %ChartConfigurationComment{}
          | %DashboardComment{}
          | %PostComment{}
          | %ShortUrlComment{}
          | %TimelineEventComment{}
          | %WalletHuntersProposalComment{}
          | %WatchlistComment{}

  @type entity ::
          :blockchain_address
          | :chart_configuration
          | :dashboard
          | :insight
          | :short_url
          | :timeline_event
          | :watchlist

  @comments_feed_entities [
    :blockchain_addresses,
    :chart_configurations,
    :dashboards,
    :insights,
    :short_urls,
    :timeline_events
  ]

  @spec create_and_link(
          entity,
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer() | nil,
          String.t()
        ) ::
          {:ok, %Comment{}} | {:error, any()}
  def create_and_link(entity, entity_id, user_id, parent_id, content) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(
      :check_can_create_comment,
      fn _repo, _changes -> Comment.can_create?(user_id) end
    )
    |> Ecto.Multi.run(
      :create_comment,
      fn _repo, _changes -> Comment.create(user_id, content, parent_id) end
    )
    |> Ecto.Multi.run(:link_comment_and_entity, fn
      _repo, %{create_comment: comment} ->
        link(entity, entity_id, comment.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{create_comment: comment}} -> {:ok, comment}
      {:error, _name, error, _} -> {:error, error}
    end
    |> emit_event(:create_comment, %{entity: entity})
  end

  @spec link(entity, non_neg_integer(), non_neg_integer()) ::
          {:ok, comment_struct} | {:error, Ecto.Changeset.t()}
  def link(entity_type, entity_id, comment_id)

  def link(:insight, entity_id, comment_id) do
    %PostComment{}
    |> PostComment.changeset(%{comment_id: comment_id, post_id: entity_id})
    |> Repo.insert()
  end

  def link(:timeline_event, entity_id, comment_id) do
    %TimelineEventComment{}
    |> TimelineEventComment.changeset(%{
      comment_id: comment_id,
      timeline_event_id: entity_id
    })
    |> Repo.insert()
  end

  def link(:blockchain_address, entity_id, comment_id) do
    %BlockchainAddressComment{}
    |> BlockchainAddressComment.changeset(%{
      comment_id: comment_id,
      blockchain_address_id: entity_id
    })
    |> Repo.insert()
  end

  def link(:dashboard, entity_id, comment_id) do
    %DashboardComment{}
    |> DashboardComment.changeset(%{
      comment_id: comment_id,
      dashboard_id: entity_id
    })
    |> Repo.insert()
  end

  def link(:short_url, entity_id, comment_id) do
    %ShortUrlComment{}
    |> ShortUrlComment.changeset(%{
      comment_id: comment_id,
      short_url_id: entity_id
    })
    |> Repo.insert()
  end

  def link(:watchlist, entity_id, comment_id) do
    %WatchlistComment{}
    |> WatchlistComment.changeset(%{
      comment_id: comment_id,
      watchlist_id: entity_id
    })
    |> Repo.insert()
  end

  def link(:chart_configuration, entity_id, comment_id) do
    %ChartConfigurationComment{}
    |> ChartConfigurationComment.changeset(%{
      comment_id: comment_id,
      chart_configuration_id: entity_id
    })
    |> Repo.insert()
  end

  def delete_all_by_entity_id(entity, entity_id) when is_number(entity_id) do
    entity_comments_query(entity, entity_id)
    |> Repo.delete_all()
  end

  @spec get_comments(entity, non_neg_integer() | nil, map()) :: [%Comment{}]
  def get_comments(entity, entity_id, %{limit: limit} = args) do
    cursor = Map.get(args, :cursor) || %{}
    order = Map.get(cursor, :order, :asc)

    entity_comments_query(entity, entity_id)
    |> apply_cursor(cursor)
    |> order_by([c], [{^order, c.inserted_at}])
    |> limit(^limit)
    |> Repo.all()
  end

  def get_comments(%{limit: limit} = args) do
    cursor = Map.get(args, :cursor) || %{}
    order = Map.get(cursor, :order, :desc)

    all_feed_comments_query()
    |> exclude_not_public_insights()
    |> exclude_not_public_chart_configurations()
    |> exclude_not_public_dashboards()
    |> apply_cursor(cursor)
    |> order_by([c], [{^order, c.id}])
    |> limit(^limit)
    |> Repo.all()
    |> transform_entity_list_to_singular()
  end

  # Private Functions

  defp maybe_add_entity_id_clause(query, _field, nil), do: query

  defp maybe_add_entity_id_clause(query, field, entity_id) do
    query
    |> where([elem], field(elem, ^field) == ^entity_id)
  end

  # Returns the comments that are associated with some of the
  # entities used in the feed
  defp all_feed_comments_query() do
    # Avoid cases where the mapping for a comment is deleted, thus
    # removing the comment from the list of comments for an entity,
    # but the comment is still in the comments table. This happens
    # when an insight is deleted for some reasons - the cascade delete
    # is not propagated to all levels.
    comment_ids_query =
      from(pc in PostComment, select: pc.comment_id)
      |> union_all(^from(pc in TimelineEventComment, select: pc.comment_id))
      |> union_all(^from(pc in BlockchainAddressComment, select: pc.comment_id))
      |> union_all(^from(pc in ShortUrlComment, select: pc.comment_id))
      |> union_all(^from(pc in ChartConfigurationComment, select: pc.comment_id))

    from(
      c in Comment,
      where: c.id in subquery(comment_ids_query),
      preload: ^@comments_feed_entities
    )
  end

  defp exclude_not_public_insights(query) do
    subquery =
      from(
        post_comment in PostComment,
        left_join: post in Sanbase.Insight.Post,
        on: post_comment.post_id == post.id,
        where: post.state != "approved" or post.ready_state != "published",
        select: post_comment.comment_id
      )

    from(
      c in query,
      where: c.id not in subquery(subquery)
    )
  end

  defp exclude_not_public_dashboards(query) do
    subquery =
      from(
        dashboard_comment in DashboardComment,
        left_join: dashboard in Sanbase.Dashboard.Schema,
        on: dashboard_comment.dashboard_id == dashboard.id,
        where: dashboard.is_public != true,
        select: dashboard_comment.comment_id
      )

    from(
      c in query,
      where: c.id not in subquery(subquery)
    )
  end

  defp exclude_not_public_chart_configurations(query) do
    subquery =
      from(
        chart_configuration_comment in ChartConfigurationComment,
        left_join: config in Sanbase.Chart.Configuration,
        on: chart_configuration_comment.chart_configuration_id == config.id,
        where: config.is_public != true,
        select: chart_configuration_comment.comment_id
      )

    from(
      c in query,
      where: c.id not in subquery(subquery)
    )
  end

  # Since polymorphic comments are modeled with many_to_many :through but the actual
  # association is belongs_to, like `comment` belongs_to `insight` we need to
  # transform preloaded entities like so: insights: [%{}] -> insight: %{}
  defp transform_entity_list_to_singular(comments) do
    comments
    |> Enum.map(fn comment ->
      @comments_feed_entities
      |> Enum.reduce(comment, fn entity, acc ->
        value = Map.get(acc, entity) |> List.first()

        singular_entity = Inflex.singularize(entity) |> String.to_existing_atom()

        acc
        |> Map.delete(entity)
        |> Map.put(singular_entity, value)
      end)
    end)
  end

  defp entity_comments_query(:watchlist, entity_id) do
    from(
      comment in WatchlistComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:watchlist_id, entity_id)
  end

  defp entity_comments_query(:chart_configuration, entity_id) do
    from(
      comment in ChartConfigurationComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:chart_configuration_id, entity_id)
  end

  defp entity_comments_query(:dashboard, entity_id) do
    from(
      comment in DashboardComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:dashboard_id, entity_id)
  end

  defp entity_comments_query(:timeline_event, entity_id) do
    from(
      comment in TimelineEventComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:timeline_event_id, entity_id)
  end

  defp entity_comments_query(:insight, entity_id) do
    from(comment in PostComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:post_id, entity_id)
  end

  defp entity_comments_query(:blockchain_address, entity_id) do
    from(comment in BlockchainAddressComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:blockchain_address_id, entity_id)
  end

  defp entity_comments_query(:short_url, entity_id) do
    from(comment in ShortUrlComment,
      preload: [:comment, comment: :user]
    )
    |> maybe_add_entity_id_clause(:short_url_id, entity_id)
  end

  defp apply_cursor(query, %{type: :before, datetime: datetime}) do
    from(c in query, where: c.inserted_at <= ^(datetime |> DateTime.to_naive()))
  end

  defp apply_cursor(query, %{type: :after, datetime: datetime}) do
    from(c in query, where: c.inserted_at >= ^(datetime |> DateTime.to_naive()))
  end

  defp apply_cursor(query, _), do: query
end
