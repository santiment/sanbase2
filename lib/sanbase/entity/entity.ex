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

  def maybe_filter_by_cursor(query, field, opts) do
    case Keyword.get(opts, :cursor) do
      nil ->
        query

      %{type: :before, datetime: datetime} ->
        from(
          entity in query,
          where: field(entity, ^field) <= ^datetime
        )

      %{type: :after, datetime: datetime} ->
        from(
          entity in query,
          where: field(entity, ^field) >= ^datetime
        )
    end
  end

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
      |> Sanbase.Repo.all()

    case entity_module.by_ids(entity_ids, []) do
      {:ok, result} -> {:ok, Enum.map(result, fn e -> %{entity => e} end)}
      {:error, error} -> {:error, error}
    end
  end

  defp do_get_most_voted(entity, opts) when is_atom(entity) do
    # The most voted entity could have been  made private at some point after
    # getting votes. For this reasonlook only at entities that are public. In
    # the case where the user is fetching their own entities that are with most
    # votes the filter is changed to return only the creations of that users

    entity_field = deduce_entity_field(entity)
    entity_module = deduce_entity_module(entity)
    entity_ids = entity_ids_query(entity, opts)

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
      |> Sanbase.Repo.all()

    case entity_module.by_ids(entity_ids, []) do
      {:ok, result} -> {:ok, Enum.map(result, fn e -> %{entity => e} end)}
      {:error, error} -> {:error, error}
    end
  end

  def do_get_most_voted2(entities, opts) when is_list(entities) do
    # base query
    query = from(vote in Sanbase.Vote)

    # Filter only rows that are related to the given entities
    query =
      Enum.reduce(entities, query, fn entity, query_acc ->
        entity_ids_query = entity_ids_query(entity, opts)
        field = deduce_entity_field(entity)

        query_acc
        |> or_where([v], field(v, ^field) in subquery(entity_ids_query))
      end)

    query =
      from(
        v in query,
        group_by: [v.post_id, v.watchlist_id, v.timeline_event_id, v.chart_configuration_id],
        order_by: [desc: coalesce(sum(v.count), 0)]
      )
      |> paginate(opts)

    # For simplicity include all the entities in the query here. The ones that are
    # not wanted have their rows excluded in the above build where clause.
    query =
      from(v in query,
        select: %{
          votes: sum(v.count),
          entity_id:
            fragment("""
            CASE
              WHEN post_id IS NOT NULL THEN post_id
              WHEN watchlist_id IS NOT NULL THEN watchlist_id
              WHEN timeline_event_id IS NOT NULL THEN timeline_event_id
              WHEN chart_configuration_id IS NOT NULL THEN chart_configuration_id
            END
            """),
          entity_type:
            fragment("""
            CASE
              WHEN post_id IS NOT NULL THEN 'insight'
              WHEN watchlist_id IS NOT NULL THEN 'watchlist'
              WHEN timeline_event_id IS NOT NULL THEN 'timeline_event'
              WHEN chart_configuration_id IS NOT NULL THEN 'chart_configuration'
            END
            """)
        }
      )

    db_result = Sanbase.Repo.all(query)

    ordering =
      db_result
      |> Enum.with_index()
      |> IO.inspect(label: "171", limit: :infinity)
      |> Map.new(fn {elem, pos} ->
        {{String.to_existing_atom(elem.entity_type), elem.entity_id}, pos}
      end)

    result =
      db_result
      |> Enum.group_by(&String.to_existing_atom(&1.entity_type), & &1.entity_id)
      |> Enum.flat_map(fn {entity, ids} ->
        entity_module = deduce_entity_module(entity)

        {:ok, data} = entity_module.by_ids(ids, [])
        Enum.map(data, fn e -> %{entity => e} end)
      end)
      |> IO.inspect(label: "184", limit: :infinity)

    result =
      result
      |> Enum.sort_by(fn map ->
        [{key, value}] = Map.to_list(map)
        Map.get(ordering, {key, value.id})
      end)

    {:ok, result}
  end

  def do_get_most_voted3(entities, opts) do
    query = from(vote in Sanbase.Vote)

    # Filter only rows that are related to the given entities
    # These are the rows where one of the wanted entities id is
    # not null. Ther is one such non-null value per row.
    query =
      Enum.reduce(entities, query, fn entity, query_acc ->
        field = deduce_entity_field(entity)

        query_acc
        |> or_where([v], not is_nil(field(v, ^field)))
      end)

    # For simplicity include all the entities in the query here. The ones that are
    # not wanted have their rows excluded in the above build where clause.
    query =
      from(
        v in query,
        group_by: [v.post_id, v.watchlist_id, v.timeline_event_id, v.chart_configuration_id],
        order_by: [desc: coalesce(sum(v.count), 0)],
        select: %{
          votes: coalesce(sum(v.count), 0),
          entity_id:
            fragment("""
            CASE
              WHEN post_id IS NOT NULL THEN post_id
              WHEN watchlist_id IS NOT NULL THEN watchlist_id
              WHEN timeline_event_id IS NOT NULL THEN timeline_event_id
              WHEN chart_configuration_id IS NOT NULL THEN chart_configuration_id
            END
            """),
          entity_type:
            fragment("""
            CASE
              WHEN post_id IS NOT NULL THEN 'insight'
              WHEN watchlist_id IS NOT NULL THEN 'watchlist'
              WHEN timeline_event_id IS NOT NULL THEN 'timeline_event'
              WHEN chart_configuration_id IS NOT NULL THEN 'chart_configuration'
            END
            """)
        }
      )
      |> paginate(opts)

    Sanbase.Repo.all(query)
  end

  defp entity_ids_query(:insight, opts) do
    entity_opts = [preload?: false, distinct?: false, cursor: opts[:cursor]]

    case Keyword.get(opts, :current_user_data_only) do
      nil -> Post.public_entity_ids_query(entity_opts)
      user_id -> Post.user_entity_ids_query(user_id, entity_opts)
    end
  end

  defp entity_ids_query(:screener, opts) do
    entity_opts = [is_screener: true, cursor: opts[:cursor]]

    case Keyword.get(opts, :current_user_data_only) do
      nil -> UserList.public_entity_ids_query(entity_opts)
      user_id -> UserList.user_entity_ids_query(user_id, entity_opts)
    end
  end

  defp entity_ids_query(:watchlist, opts) do
    entity_opts = [is_screener: false, cursor: opts[:cursor]]

    case Keyword.get(opts, :current_user_data_only) do
      nil -> UserList.public_entity_ids_query(entity_opts)
      user_id -> UserList.user_entity_ids_query(user_id, entity_opts)
    end
  end

  defp entity_ids_query(:chart_configuration, opts) do
    entity_opts = [cursor: opts[:cursor]]

    case Keyword.get(opts, :current_user_data_only) do
      nil -> Chart.Configuration.public_entity_ids_query(entity_opts)
      user_id -> Chart.Configuration.user_entity_ids_query(user_id, entity_opts)
    end
  end

  defp entity_ids_query(:timeline_event, opts) do
    entity_opts = [cursor: opts[:cursor]]

    case Keyword.get(opts, :current_user_data_only) do
      nil -> TimelineEvent.public_entity_ids_query(entity_opts)
      user_id -> TimelineEvent.user_entity_ids_query(user_id, entity_opts)
    end
  end

  defp deduce_entity_module(:insight), do: Post
  defp deduce_entity_module(:watchlist), do: UserList
  defp deduce_entity_module(:screener), do: UserList
  defp deduce_entity_module(:timeline_event), do: TimelineEvent
  defp deduce_entity_module(:chart_configuration), do: Chart.Configuration

  defp maybe_filter_by_cursor(query, entity_type, opts) do
    case Keyword.get(opts, :cursor) do
      nil -> query
      %{type: type, datetime: datetime} -> filter_by_cursor(type, query, entity_type, datetime)
    end
  end

  # In the case of most voted API the Vote table is joined with the
  # entity table, so we need to access the entity from that joined table.
  # In the other case there are no joins. Solve this difference by
  # using named bindings in both cases.
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
