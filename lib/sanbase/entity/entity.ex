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

  # The list of supported entitiy types. In order to add a new entity type, the
  # following steps must be taken:
  # 1. Implement the Sanbase.Entity behaviour in the entity module. It forces
  # implementation of functions that generate the SQL query and fetch entities
  # by ids in a given order.`
  # 2. Implement the public function deduce_entity_type/1 in this module
  # 3. Implement the private functions entity_ids_query/2 and
  #    deduce_entity_module/1 in this module
  # 4. Extend the CASE blocks and the group_by clause in the do_get_most_voted/2
  # 5. Check if extending the deduce_entity_creation_time_field/1 is necessary.
  #    It is necessary if the new entity needs to use a different than
  #    inserted_at field to check its creation time. For example, insights have
  #    their published_at time taken, not inserted_at
  @supported_entity_type [:insight, :watchlist, :screener, :chart_configuration]

  def get_most_voted(entity_or_entities, opts),
    do: do_get_most_voted(List.wrap(entity_or_entities), opts)

  def get_most_recent(entity_or_entities, opts),
    do: do_get_most_recent(List.wrap(entity_or_entities), opts)

  @doc ~s"""
  Map the entity type to the corresponding field in the votes table
  """
  def deduce_entity_vote_field(:insight), do: :post_id
  def deduce_entity_vote_field(:watchlist), do: :watchlist_id
  def deduce_entity_vote_field(:screener), do: :watchlist_id
  def deduce_entity_vote_field(:chart_configuration), do: :chart_configuration_id
  # keep the timeline_event here so it can have its id obtained by the Vote module
  def deduce_entity_vote_field(:timeline_event), do: :timeline_event_id

  @doc ~s"""
  Apply the pagination options from `opts` to `query`.

  The `opts` are expected to contain the `page` and `page_size` keys with
  interes bigger or equal to 1 as values.
  The query is expected to have an ordering applied to it (before or after calling paginate)
  so the pagination has meaning.
  """
  @spec paginate(Ecto.Query.t(), pagination_opts) :: Ecto.Query.t()
        when pagination_opts: [page: non_neg_integer(), page_size: non_neg_integer()]
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

    # Filter only rows that are related to the given entities. For every type in
    # the entities list build a query that returns the entity id, entity type
    # and the creation time as a map. These queries have the same field names
    # (inserted_at/published_at are renamed) so they can be combined with a
    # UNION. This is required as the result must pull data from multiple tables
    # with different schemas.
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

    # Add pagination to the query. This uses the new map of arguments built
    # by the base query above. This allows to have a creation time field
    # with the same name, so we can properly sort the results before applying
    # limit and offset.
    query =
      from(
        entity in subquery(query),
        order_by: [desc: entity.creation_time, desc: entity.entity_id]
      )
      |> paginate(opts)

    db_result = Sanbase.Repo.all(query)

    result = fetch_entities_by_ids(db_result)

    # Order the full list of entities by the creation time in descending order.
    # The end result is a list like:
    # [%{watchlist: w}, %{insight: i}, %{chart_configuration: c}, %{screener: s}]
    sorted_result =
      Enum.sort_by(
        result,
        fn elem ->
          [{key, entity}] = Map.to_list(elem)

          Map.get(entity, deduce_entity_creation_time_field(key))
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

    # Base query. The required ids are fetched from the votes table, where voting
    # for every entity type is stored. Every type uses its own column that bears the
    # enitity type name + _id suffix.
    query = from(vote in Sanbase.Vote)

    # Filter only rows that are related to the given entities. This is done by
    # building a list of where clauses join with OR. For every type in the
    # entities, add a where clause that filters the rows that have the id that
    # is included in the subquery. Watchlists and screener are both represented
    # by the watchlist_id column but their subqueries are disjoint - they never
    # share ids.
    query =
      Enum.reduce(entities, query, fn entity, query_acc ->
        entity_ids_query = entity_ids_query(entity, opts)
        field = deduce_entity_vote_field(entity)

        query_acc
        |> or_where([v], field(v, ^field) in subquery(entity_ids_query))
      end)

    # Add ordering and pagination. The group by is required so we can count
    # all the votes for each entity. There is exactly one non-null entity id per
    # row, so the chosen group by expression is working as expected.
    query =
      from(
        v in query,
        group_by: [v.post_id, v.watchlist_id, v.chart_configuration_id],
        order_by: [desc: coalesce(sum(v.count), 0)]
      )
      |> paginate(opts)

    # For simplicity include all the known in the query here. The ones that are
    # not wanted have their rows excluded in the above build where clause and
    # will never match in the case statement.
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
              -- the watchlist_id can point to either screener or watchlist. This is handled later.
              WHEN watchlist_id IS NOT NULL THEN 'watchlist'
              WHEN chart_configuration_id IS NOT NULL THEN 'chart_configuration'
            END
            """)
        }
      )

    db_result = Sanbase.Repo.all(query)

    # The result is returned in descending order based on votes. This order will
    # be lost once we split the result into different entity type groups is
    # order to fetch them. In order to preserve the order, we need to record it
    # beforehand. This is done by making a map where the keys are {entity_type,
    # entity_id} and the value is the position in the original result.
    # NOTE 1: As we are recording the position in the original result, we need
    # to sort the result in ASCENDING order at the end. NOTE 2: The db_result
    # from here includes only the entity id and entity type. This is not enough
    # to distinguish between screener and watchlist. This will be done once the
    # full objects are returned.
    ordering =
      db_result
      |> Enum.with_index()
      |> Map.new(fn {elem, pos} ->
        {{String.to_existing_atom(elem.entity_type), elem.entity_id}, pos}
      end)

    result = fetch_entities_by_ids(db_result)

    # Sort in ascending order according to the ordering map
    result =
      result
      |> Enum.sort_by(fn map ->
        [{key, value}] = Map.to_list(map)
        Map.get(ordering, {key, value.id})
      end)

    result = rewrite_keys(result)

    {:ok, result}
  end

  defp fetch_entities_by_ids(list) do
    # Group the results by entity type and fetch the full entities from the
    # database. Every entity is then represented as a map with the entity as
    # value and its type as a key. This is required as the GraphQL API needs to
    # match every different type to a GraphQL type. The end result is a list like
    # [%{watchlist: w}, %{insight: i}, %{chart_configuration: c}, %{screener: s}]
    list
    |> Enum.group_by(&String.to_existing_atom(&1.entity_type), & &1.entity_id)
    |> Enum.flat_map(fn {entity, ids} ->
      entity_module = deduce_entity_module(entity)

      {:ok, data} = entity_module.by_ids(ids, [])
      Enum.map(data, fn e -> %{entity => e} end)
    end)
  end

  defp rewrite_keys(list) do
    Enum.map(list, fn elem ->
      case Map.to_list(elem) do
        # Check if the watchlist is a screener so we can rewrite its name.
        # Screeners are watchlists so in the votes table their votes are stored
        # in the watchlist_id column
        [{:watchlist, watchlist}] ->
          case UserList.is_screener?(watchlist) do
            true -> %{screener: watchlist}
            false -> %{watchlist: watchlist}
          end

        # Check if the argument is in the right format. If this was a catch-all
        # case then wrong arugment types would still be passed through here without
        # any changes.
        [{type, entity}] when type in @supported_entity_type ->
          %{type => entity}
      end
    end)
  end

  defp entity_ids_query(:insight, opts) do
    # `ordered?: false` is important otherwise the default order will be
    # applied and this will conflict with the distinct(true) check
    entity_opts = [preload?: false, distinct?: true, ordered?: false, cursor: opts[:cursor]]

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
