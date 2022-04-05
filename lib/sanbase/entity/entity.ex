defmodule Sanbase.Entity do
  @moduledoc ~s"""
  Provide unified access to all sanbase defined entities.

  Entities include:
  - Insight
  - Watchlist
  - Screener
  - Timeline Event
  - Chart Configuration

  This module provides functions for fetching lists of entities of a given type,
  ordered in a specific way. There are two orderings:
  - most recent first
  - most voted first
  """
  import Ecto.Query

  alias Sanbase.Chart
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Timeline.TimelineEvent

  def paginate(query, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  def get_most_voted(entity, opts), do: do_get_most_voted(entity, opts)

  def get_most_recent(entity, opts), do: do_get_most_recent(entity, opts)

  def deduce_entity_field(:insight), do: :post_id
  def deduce_entity_field(:watchlist), do: :watchlist_id
  def deduce_entity_field(:screener), do: :watchlist_id
  def deduce_entity_field(:timeline_event), do: :timeline_event_id
  def deduce_entity_field(:chart_configuration), do: :chart_configuration_id

  # Private functions

  defp do_get_most_recent(entity, opts) do
    # The most recent entity could be a private one. For this reasonlook only at
    # entities that are public. In the case where the user is fetching their own
    # entities that are with most votes the filter is changed to return only the
    # creations of that users

    entity_ids = entity_ids_query(entity, opts)
    entity_module = deduce_entity_module(entity)

    # Add named binding as it is used in the subquery to avoid issues where one
    # query needs to access the right joined table and the other does not have
    # joins.
    entity_ids =
      from(
        entity in entity_module,
        as: :entity,
        select: entity.id,
        where: entity.id in subquery(entity_ids),
        order_by: [desc: entity.id]
      )
      |> paginate(opts)
      |> maybe_filter_by_cursor(entity, opts)
      |> Sanbase.Repo.all()

    case entity_module.by_ids(entity_ids, []) do
      {:ok, result} -> {:ok, Enum.map(result, fn e -> %{entity => e} end)}
      {:error, error} -> {:error, error}
    end
  end

  defp do_get_most_voted(entity, opts) do
    # The most voted entity could have been  made private at some point after
    # getting votes. For this reasonlook only at entities that are public. In
    # the case where the user is fetching their own entities that are with most
    # votes the filter is changed to return only the creations of that users

    entity_field = deduce_entity_field(entity)
    entity_module = deduce_entity_module(entity)
<<<<<<< HEAD
    entity_ids = entity_ids_query(entity, opts)
=======
    entity_ids = entity_ids_query(entity)
>>>>>>> a0a21c8cd (Improve/simplify Post sql queries)

    # Add named binding as it is used in the subquery to avoid issues where one
    # query needs to access the right joined table and the other does not have
    # joins.
    entity_ids =
      from(
        vote in Sanbase.Vote,
        right_join: entity in ^entity_module,
        as: :entity,
        on: field(vote, ^entity_field) == entity.id,
        where: entity.id in subquery(entity_ids),
        group_by: entity.id,
        select: entity.id,
        order_by: [desc: coalesce(sum(vote.count), 0), desc: entity.id]
      )
      |> paginate(opts)
      |> maybe_filter_by_cursor(entity, opts)
      |> Sanbase.Repo.all()

    case entity_module.by_ids(entity_ids, []) do
      {:ok, result} -> {:ok, Enum.map(result, fn e -> %{entity => e} end)}
      {:error, error} -> {:error, error}
    end
  end

  defp entity_ids_query(:insight, opts) do
    post_opts = [preload?: false, distinct?: false]

    case Keyword.get(opts, :current_user_data_only) do
      nil -> Post.public_entity_ids_query(post_opts)
      user_id -> Post.user_entity_ids_query(user_id, post_opts)
    end
  end

  defp entity_ids_query(:screener, opts) do
    case Keyword.get(opts, :current_user_data_only) do
      nil -> UserList.public_entity_ids_query(is_screener: true)
      user_id -> UserList.user_entity_ids_query(user_id, is_screener: true)
    end
  end

  defp entity_ids_query(:watchlist, opts) do
    case Keyword.get(opts, :current_user_data_only) do
      nil -> UserList.public_entity_ids_query(is_screener: false)
      user_id -> UserList.user_entity_ids_query(user_id, is_screener: false)
    end
  end

  defp entity_ids_query(:chart_configuration, opts) do
    case Keyword.get(opts, :current_user_data_only) do
      nil -> Chart.Configuration.public_entity_ids_query([])
      user_id -> Chart.Configuration.user_entity_ids_query(user_id, [])
    end
  end

  defp entity_ids_query(:timeline_event, opts) do
    case Keyword.get(opts, :current_user_data_only) do
      nil -> TimelineEvent.public_entity_ids_query([])
      user_id -> TimelineEvent.user_entity_ids_query(user_id, [])
    end
  end


  defp deduce_entity_module(:insight), do: Post
  defp deduce_entity_module(:watchlist), do: UserList
  defp deduce_entity_module(:screener), do: UserList
  defp deduce_entity_module(:timeline_event), do: TimelineEvent
  defp deduce_entity_module(:chart_configuration), do: Chart.Configuration

  defp maybe_filter_by_cursor(query, entity_type, opts) do
    case Keyword.get(opts, :cursor) do
      nil ->
        query

      %{type: type, datetime: datetime} ->
        filter_by_cursor(type, query, entity_type, datetime)
    end
  end

  # In the case of most voted API the Vote table is joined with the entity
  # table, so we need to access the entity from that joined table. In the other
  # case there are no joins. Solve this difference by using named bindings in
  # both cases.
  defp filter_by_cursor(:before, query, entity_type, datetime) do
    field = entity_datetime_field(entity_type)

    from(
      [entity: entity] in query,
      where: field(entity, ^field) <= ^datetime
    )
  end

  defp filter_by_cursor(:after, query, entity_type, datetime) do
    field = entity_datetime_field(entity_type)

    from(
      [entity: entity] in query,
      where: field(entity, ^field) >= ^datetime
    )
  end

  # Insights are considered created once they are published
  defp entity_datetime_field(:insight), do: :published_at
  defp entity_datetime_field(_), do: :inserted_at
end
