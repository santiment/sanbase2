defmodule Sanbase.Entity do
  @moduledoc ~s"""
  Provide unified access to all sanbase defined entities.

  Entities include:
  - Insight
  - Watchlist
  - Screener
  - Chart Configuration
  Entities to be included:
  - Alerts
  - Address Watchlist

  This module provides functions for fetching lists of entities of a given type,
  ordered in a specific way. There are two orderings:
  - most recent first
  - most voted first
  """
  import Ecto.Query

  alias Sanbase.Chart
  alias Sanbase.Insight.Post
  alias Sanbase.UserList

  def get_most_voted(entity_or_entities, opts),
    do: do_get_most_voted(List.wrap(entity_or_entities), opts)

  def get_most_recent(entity_or_entities, opts),
    do: do_get_most_recent(List.wrap(entity_or_entities), opts)

  def deduce_entity_field(:insight), do: :post_id
  def deduce_entity_field(:watchlist), do: :watchlist_id
  def deduce_entity_field(:screener), do: :watchlist_id
  def deduce_entity_field(:chart_configuration), do: :chart_configuration_id

  def paginate(query, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  @doc ~s"""
  Apply a datetime filter, if defined in the opts, to a query.

  This query extension function is defined here and is called with the
  proper arguments from the entity modules' functions.
  """
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

  defp do_get_most_recent(entities, opts) when is_list(entities) and entities != [] do
    # The most recent entity could be a private one. For this reasonlook only at
    # entities that are public. In the case where the user is fetching their own
    # entities that are with most votes the filter is changed to return only the
    # creations of that users

    # Filter only rows that are related to the given entities
    query =
      Enum.reduce(entities, nil, fn entity, query_acc ->
        entity_ids_query = entity_ids_query(entity, opts)
        creation_time_field = deduce_entity_creation_time_field(entity)

        entity_query =
          from(entity in entity_ids_query)
          # Remove the existing `entity.id` select and replace it with another one
          |> exclude(:select)
          |> select([e], %{
            entity_id: e.id,
            entity_type: ^"#{entity}",
            creation_time: field(e, ^creation_time_field)
          })

        case query_acc do
          nil ->
            entity_query

          query_acc ->
            query_acc
            |> union(^entity_query)
        end
      end)

    query =
      from(
        entity in subquery(query),
        order_by: [desc: entity.creation_time, desc: entity.entity_id]
      )
      |> paginate(opts)

    db_result = Sanbase.Repo.all(query)

    result =
      db_result
      |> Enum.group_by(&String.to_existing_atom(&1.entity_type), & &1.entity_id)
      |> Enum.flat_map(fn {entity, ids} ->
        entity_module = deduce_entity_module(entity)

        {:ok, data} = entity_module.by_ids(ids, [])
        Enum.map(data, fn e -> %{entity => e} end)
      end)

    sorted_result =
      Enum.sort_by(
        result,
        fn elem ->
          [entity] = Map.values(elem)

          Map.get(entity, deduce_entity_creation_time_field(entity))
        end,
        {:desc, NaiveDateTime}
      )

    {:ok, sorted_result}
  end

  defp do_get_most_voted(entities, opts) when is_list(entities) do
    # The most voted entity could have been  made private at some point after
    # getting votes. For this reasonlook only at entities that are public. In
    # the case where the user is fetching their own entities that are with most
    # votes the filter is changed to return only the creations of that users

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
        group_by: [v.post_id, v.watchlist_id, v.chart_configuration_id],
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
              WHEN chart_configuration_id IS NOT NULL THEN chart_configuration_id
            END
            """),
          entity_type:
            fragment("""
            CASE
              WHEN post_id IS NOT NULL THEN 'insight'
              WHEN watchlist_id IS NOT NULL THEN 'watchlist'
              WHEN chart_configuration_id IS NOT NULL THEN 'chart_configuration'
            END
            """)
        }
      )

    db_result = Sanbase.Repo.all(query)

    ordering =
      db_result
      |> Enum.with_index()
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

    result =
      result
      |> Enum.sort_by(fn map ->
        [{key, value}] = Map.to_list(map)
        Map.get(ordering, {key, value.id})
      end)

    result = rewrite_keys(result)

    {:ok, result}
  end

  defp rewrite_keys(list) do
    Enum.map(list, fn
      %{watchlist: watchlist} ->
        case UserList.is_screener?(watchlist) do
          true -> %{screener: watchlist}
          false -> %{watchlist: watchlist}
        end

      elem ->
        elem
    end)
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

  defp deduce_entity_module(:insight), do: Post
  defp deduce_entity_module(:watchlist), do: UserList
  defp deduce_entity_module(:screener), do: UserList
  defp deduce_entity_module(:chart_configuration), do: Chart.Configuration

  defp deduce_entity_creation_time_field(:insight), do: :published_at
  defp deduce_entity_creation_time_field(_), do: :inserted_at
end
