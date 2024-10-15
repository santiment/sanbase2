defmodule Sanbase.Entity do
  @moduledoc ~s"""
  Provide unified access to all sanbase defined entities.

  Entities include:
  - Insight
  - Watchlist
  - Screener
  - Chart Configuration
  - Alerts
  - Address Watchlist

  This module provides functions for fetching lists of entities or counts of entities of a given type,
  ordered in a specific way. There are two orderings:
  - Most recent first
  - Most voted first

  ## Shared Options

  Almost all of the repository functions outlined in this module accept the following
  options:
    * `:page` - The page as a positive integer when fetching lists of entities.
    * `:page_size` - The page size as a positive integer when fetching lists of entities
    * `:cursor` - A map that serves as a datetime filter. It contains two fields - :type,
       that can be either :before or :after and a :datetime, which is a DateTime.t() struct.
  """
  import Ecto.Query
  import Sanbase.Entity.Query, only: [entity_id_selection: 0, entity_type_selection: 0]

  alias Sanbase.Chart
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Queries.Query
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Accounts.Interaction

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
  @supported_entity_type [
    :insight,
    :watchlist,
    :screener,
    :chart_configuration,
    :user_trigger,
    :dashboard,
    :query
  ]

  @type entity_id :: non_neg_integer() | String.t()

  @type entity_type ::
          :insight
          | :watchlist
          | :screener
          | :chart_configuration
          | :user_trigger
          | :dashboard
          | :query

  @type option ::
          {:page, non_neg_integer()}
          | {:page_size, non_neg_integer()}
          | {:cursor, map()}
          | {:user_ids, list(non_neg_integer())}

  @type opts :: [option]
  @type result_map :: %{
          optional(:insight) => %Post{},
          optional(:screener) => %UserTrigger{},
          optional(:project_watchlist) => %UserTrigger{},
          optional(:address_watchlist) => %UserTrigger{},
          optional(:chart_configuration) => %Chart.Configuration{},
          optional(:user_trigger) => %UserTrigger{},
          optional(:dashboard) => %Dashboard{},
          optional(:query) => %Query{}
        }

  @spec get_visibility_data(entity_type, entity_id) :: {:ok, map()} | {:error, String.t()}
  def get_visibility_data(entity_type, entity_id) do
    module = deduce_entity_module(entity_type)

    apply(module, :get_visibility_data, [entity_id])
  end

  @doc ~s"""
  Get a list of the most voted entities of a given type or types.
  The ordering is done by taking into consideration all of the types and is not
  done on a per-type basis.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @spec get_most_voted(entity_type | [entity_type], opts) :: {:ok, list(result_map)} | no_return()
  def get_most_voted(type_or_types, opts),
    do: do_get_most_voted(List.wrap(type_or_types), opts)

  @doc ~s"""
  Get a list of the most recent entities of a given type or types.
  The ordering is done by taking into consideration all of the types and is not
  done on a per-type basis.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @spec get_most_recent(entity_type | [entity_type], opts) ::
          {:ok, list(result_map)} | no_return()
  def get_most_recent(type_or_types, opts),
    do: do_get_most_recent(List.wrap(type_or_types), opts)

  @doc ~s"""
  Get a list of the most used entities of a given type or types.
  The ordering is done by taking into consideration the amount of views and
  other activity types (votes, comments, etc.) a given entity has.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @spec get_most_used(entity_type | [entity_type], opts) ::
          {:ok, list(result_map)} | no_return()
  def get_most_used(type_or_types, opts),
    do: do_get_most_used(List.wrap(type_or_types), opts)

  @doc ~s"""
  Get the total count of voted entities of a given type or types.
  A cursor can be applied, but pagination cannot.
  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @spec get_most_voted_total_count(entity_type | [entity_type], opts) ::
          {:ok, non_neg_integer()} | no_return()
  def get_most_voted_total_count(type_or_types, opts),
    do: do_get_most_voted_total_count(List.wrap(type_or_types), opts)

  @doc ~s"""
  Get the total count of entities of a given type or types.
  A cursor can be applied, but pagination cannot.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @spec get_most_recent_total_count(entity_type | [entity_type], opts) ::
          {:ok, non_neg_integer()} | no_return()
  def get_most_recent_total_count(type_or_types, opts),
    do: do_get_most_recent_total_count(List.wrap(type_or_types), opts)

  @doc ~s"""
  Get the total count of used entities of a given type or types for a user.
  A cursor can be applied, but pagination cannot.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.
  """
  @spec get_most_used_total_count(entity_type | [entity_type], opts) ::
          {:ok, non_neg_integer()} | no_return()
  def get_most_used_total_count(type_or_types, opts),
    do: do_get_most_used_total_count(List.wrap(type_or_types), opts)

  @doc ~s"""
  Map the entity type to the corresponding field in the votes table
  """
  def deduce_entity_vote_field(:user_trigger), do: :user_trigger_id
  def deduce_entity_vote_field(:insight), do: :post_id
  def deduce_entity_vote_field(:post), do: :post_id
  def deduce_entity_vote_field(:watchlist), do: :watchlist_id
  def deduce_entity_vote_field(:project_watchlist), do: :watchlist_id
  def deduce_entity_vote_field(:address_watchlist), do: :watchlist_id
  def deduce_entity_vote_field(:screener), do: :watchlist_id
  def deduce_entity_vote_field(:chart_configuration), do: :chart_configuration_id
  def deduce_entity_vote_field(:dashboard), do: :dashboard_id
  def deduce_entity_vote_field(:query), do: :query_id
  def deduce_entity_vote_field(:timeline_event), do: :timeline_event_id

  # This needs to stay here even though it's not a supported entity type by the
  # API. This is because internally all watchlist/screener types are stored as
  # watchlists and we need to be able to know from which module to call by_ids/2
  # so the objects can be fetched. Only when the full object is fetched we can
  # call rewrite_keys/1 and put the proper key
  def deduce_entity_module(:watchlist), do: UserList
  def deduce_entity_module(:project_watchlist), do: UserList
  def deduce_entity_module(:address_watchlist), do: UserList
  def deduce_entity_module(:screener), do: UserList
  def deduce_entity_module(:user_trigger), do: UserTrigger
  def deduce_entity_module(:insight), do: Post
  def deduce_entity_module(:chart_configuration), do: Chart.Configuration
  def deduce_entity_module(:dashboard), do: Dashboard
  def deduce_entity_module(:query), do: Query

  def by_id(entity_type, entity_id) do
    module = deduce_entity_module(entity_type)
    apply(module, :by_id, [entity_id, []])
  end

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

  def extend_with_views_count(type_entity_list) do
    # The type_entity_list is a list of maps like %{screener: %UserList{id: 1}}
    # The function returns the same list of entities, with each
    # entity now having the virtual ecto field :views populated
    entity_views_query = entity_views_query(type_entity_list)

    entity_count_map =
      Sanbase.Repo.all(entity_views_query)
      |> Enum.into(%{}, fn {entity_type, entity_id, views_count} ->
        {{entity_type, entity_id}, views_count}
      end)

    Enum.map(type_entity_list, fn type_entity ->
      [{type, entity}] = Map.to_list(type_entity)
      key = {Interaction.deduce_entity_column_name(type), entity.id}
      entity = %{entity | views: entity_count_map[key] || 0}
      %{type => entity}
    end)
  end

  # Private functions

  defp entity_views_query(type_entity_list) do
    entity_type_id_conditions = views_count_entity_type_id_conditions(type_entity_list)
    # When executed, the query returns a list of 3-element tuples
    # {entity_type, entity_id, views_count}

    from(row in Interaction,
      where: ^entity_type_id_conditions,
      select: {row.entity_type, row.entity_id, fragment("COUNT(*)")},
      group_by: [row.entity_type, row.entity_id]
    )
  end

  defp views_count_entity_type_id_conditions(type_entity_list) do
    # Build the ecto where clause that gets the rows for each of the entities.
    # It will look like: (row.entity_type == "screener" and row.entity_id = 1) or ( ... )
    dynamic_query =
      Enum.reduce(type_entity_list, false, fn type_entity, dynamic_query ->
        [{type, %{id: entity_id}}] = Map.to_list(type_entity)
        type = Interaction.deduce_entity_column_name(type)

        dynamic(
          [row],
          ^dynamic_query or (row.entity_type == ^type and row.entity_id == ^entity_id)
        )
      end)

    dynamic([row], row.interaction_type == "view" and ^dynamic_query)
  end

  defp do_get_most_recent_total_count(entities, opts) when is_list(entities) and entities != [] do
    opts = update_opts(opts)
    {:ok, query} = most_recent_base_query(entities, opts)

    total_count =
      from(entity in subquery(query),
        select: fragment("COUNT(DISTINCT(?, ?))", entity.entity_id, entity.entity_type)
      )
      |> Sanbase.Repo.one()

    {:ok, total_count}
  end

  defp do_get_most_voted_total_count(entities, opts) when is_list(entities) and entities != [] do
    opts = update_opts(opts)
    {:ok, query} = most_voted_base_query(entities, opts)

    # Convert the rows to a list of entity_id and entity_type. This is because otherwise
    # we count the total number of voters as every differnt user's vote is on its own
    # row. On this transformed row it is possible to easily apply DISTINCT before
    # COUNT, so every entity is counted only once.
    query =
      from(
        v in query,
        select: %{entity_id: entity_id_selection(), entity_type: entity_type_selection()}
      )

    total_count =
      from(entity in subquery(query),
        select: fragment("COUNT(DISTINCT(?, ?))", entity.entity_id, entity.entity_type)
      )
      |> Sanbase.Repo.one()

    {:ok, total_count}
  end

  defp do_get_most_recent(entities, opts) when is_list(entities) and entities != [] do
    opts = update_opts(opts)
    {:ok, query} = most_recent_base_query(entities, opts)

    # Add pagination to the query. This uses the new map of arguments built by
    # the base query above. This allows to have a creation time field with the
    # same name, so we can properly sort the results before applying limit and
    # offset.
    query =
      from(
        entity in subquery(query),
        order_by: [desc: entity.creation_time, desc: entity.entity_id]
      )
      |> paginate(opts)

    db_result = Sanbase.Repo.all(query)

    result = fetch_entities_by_ids(db_result)

    # Order the full list of entities by the creation time in descending order.
    # The end result is a list like: [%{project_watchlist: w}, %{insight: i},
    # %{chart_configuration: c}, %{screener: s}, %{address_watchlist: a}]
    sorted_result =
      Enum.sort_by(
        result,
        fn elem ->
          [{type, entity}] = Map.to_list(elem)

          {creation_time_field, creation_time_field_backup} =
            deduce_entity_creation_time_field(type)

          # In all cases the fields are the same except for insights. When
          # fetching user own insights, some of them might be drafts so they
          # won't have :published_at field and then :inserted_at shall be used.
          creation_time =
            Map.get(entity, creation_time_field) || Map.get(entity, creation_time_field_backup)

          creation_time_unix =
            DateTime.from_naive!(creation_time, "Etc/UTC") |> DateTime.to_unix()

          # Transform to unix timestamp so we can compare the tuples. Add the id as the secon
          # element so in case of conflicts, we put the entity with higher id first (created later)
          {creation_time_unix, Map.get(entity, :id)}
        end,
        :desc
      )

    {:ok, sorted_result}
  end

  defp do_get_most_voted(entities, opts) when is_list(entities) and entities != [] do
    opts = update_opts(opts)
    {:ok, query} = most_voted_base_query(entities, opts)

    # Add ordering and pagination. The group by is required so we can count all
    # the votes for each entity. There is exactly one non-null entity id per
    # row, so the chosen group by expression is working as expected.
    query =
      from(
        v in query,
        group_by: [
          v.post_id,
          v.watchlist_id,
          v.chart_configuration_id,
          v.user_trigger_id,
          v.dashboard_id,
          v.query_id
        ]
      )
      |> paginate(opts)

    query =
      case Keyword.get(opts, :current_user_voted_for_only) do
        user_id when is_integer(user_id) ->
          query
          |> order_by([_v],
            desc: fragment("MAX(updated_at) FILTER (WHERE user_id = ?)", ^user_id)
          )

        _ ->
          query
          |> order_by([v], desc: coalesce(sum(v.count), 0))
      end

    # For simplicity include all the known in the query here. The ones that are
    # not wanted have their rows excluded in the above build where clause and
    # will never match in the case statement.
    query =
      from(v in query,
        select: %{
          votes: sum(v.count),
          entity_id: entity_id_selection(),
          entity_type: entity_type_selection()
        }
      )

    result =
      query
      |> Sanbase.Repo.all()
      |> fetch_entities_by_ids_preserve_order_rewrite_keys()

    {:ok, result}
  end

  defp fetch_entities_by_ids_preserve_order_rewrite_keys(db_result) do
    # The result is returned in descending order based on votes. This order will
    # be lost once we split the result into different entity type groups is
    # order to fetch them. In order to preserve the order, we need to record it
    # beforehand. This is done by making a map where the keys are {entity_type,
    # entity_id} and the value is the position in the original result.
    # NOTE 1:
    # As we are recording the position in the original result, we need to sort
    # the result in ASCENDING order at the end.
    # NOTE 2:
    # The db_result from here includes only the entity id and entity type.
    # This is not enough to distinguish between screener and watchlist. This will
    # be done once the full objects are returned.
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

    result
  end

  defp do_get_most_used(entities, opts) when is_list(entities) and entities != [] do
    # The most used entities are the ones that the user has visited the most.

    # The get_most_used API is used (at the moment) only to get the querying user most
    # used entities. It should include both the public entities and the user's own
    # private entities. This is controlled by setting both `include_public_entities`
    # and `include_current_user_entities` to true
    opts = update_opts(opts)

    query = most_used_base_query(entities, opts)

    result =
      Sanbase.Repo.all(query)
      |> fetch_entities_by_ids_preserve_order_rewrite_keys()

    {:ok, result}
  end

  defp do_get_most_used_total_count(entities, opts) when is_list(entities) and entities != [] do
    opts = update_opts(opts)
    query = most_used_base_query(entities, opts)

    from(entity in subquery(query),
      select: {entity.entity_id, entity.entity_type}
    )
    |> Sanbase.Repo.all()

    total_count =
      from(entity in subquery(query),
        select: fragment("COUNT(DISTINCT(?, ?))", entity.entity_id, entity.entity_type)
      )
      |> Sanbase.Repo.one()

    {:ok, total_count}
  end

  defp most_used_base_query(entities, opts) when is_list(entities) and entities != [] do
    opts =
      opts
      |> Keyword.put(:include_public_entities, true)
      |> Keyword.put(:include_current_user_entities, true)

    query =
      Keyword.fetch!(opts, :current_user_id)
      |> Sanbase.Accounts.Interaction.get_user_most_used_query(entities, opts)

    where_clause_query =
      Enum.reduce(entities, nil, fn type, query_acc ->
        entity_ids_query = entity_ids_query(type, opts)
        entity_type_name = Sanbase.Accounts.Interaction.deduce_entity_column_name(type)

        case query_acc do
          nil ->
            dynamic(
              [row],
              row.entity_type == ^entity_type_name and row.entity_id in subquery(entity_ids_query)
            )

          _ ->
            dynamic(
              [row],
              (row.entity_type == ^entity_type_name and
                 row.entity_id in subquery(entity_ids_query)) or ^query_acc
            )
        end
      end)

    query |> where(^where_clause_query)
  end

  defp most_recent_base_query(entities, opts) when is_list(entities) and entities != [] do
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
      Enum.reduce(entities, nil, fn type, query_acc ->
        entity_ids_query = entity_ids_query(type, opts)

        {creation_time_field, creation_time_field_backup} =
          deduce_entity_creation_time_field(type)

        entity_query =
          from(entity in entity_ids_query)
          # Remove the existing `entity.id` select and replace it with another
          # one
          |> exclude(:select)
          |> select([e], %{
            entity_id: e.id,
            entity_type: ^"#{type}",
            # In all cases the fields are the same except for insights. When
            # fetching user own insights, some of them might be drafts so they
            # won't have :published_at field and then :inserted_at shall be
            # used.
            creation_time:
              coalesce(field(e, ^creation_time_field), field(e, ^creation_time_field_backup))
          })

        case query_acc do
          nil ->
            entity_query

          query_acc ->
            query_acc |> union(^entity_query)
        end
      end)

    {:ok, query}
  end

  def most_voted_base_query(entities, opts) when is_list(entities) and entities != [] do
    # The most voted entity could have been  made private at some point after
    # getting votes. For this reasonlook only at entities that are public. In
    # the case where the user is fetching their own entities that are with most
    # votes the filter is changed to return only the creations of that users

    # Base query. The required ids are fetched from the votes table, where
    # voting for every entity type is stored. Every type uses its own column
    # that bears the enitity type name + _id suffix.
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

    query =
      case Keyword.get(opts, :current_user_voted_for_only) do
        user_id when is_integer(user_id) ->
          filter_user_voted_for_entities(query, user_id)

        _ ->
          query
      end

    {:ok, query}
  end

  defp filter_user_voted_for_entities(query, user_id) do
    # Get a list of the entities that the given user has voted for. All votes
    # (between 1 and 20) are recorded on the same row in the `count` column, so
    # no `distinct` is required. These entity ids are then fed to a where clause
    # filter that will return only those entities. NOTE: We cannot just put
    # `where: vote.user_id == ^user_id` in the query as this will not properly
    # count all votes but only the votes cast by the user. This will make it
    # impossible to sort by most voted first then.
    result = get_entity_votes_for_user(user_id)

    ids_map = Enum.group_by(result, & &1.entity_type, & &1.entity_id)

    post_ids = ids_map["insight"] || []
    watchlist_ids = ids_map["watchlist"] || []
    chart_configuration_ids = ids_map["chart_configuration"] || []
    user_trigger_ids = ids_map["user_trigger"] || []
    dashboard_ids = ids_map["dashboard"] || []
    query_ids = ids_map["query"] || []

    from(v in query,
      where:
        v.post_id in ^post_ids or
          v.watchlist_id in ^watchlist_ids or
          v.chart_configuration_id in ^chart_configuration_ids or
          v.user_trigger_id in ^user_trigger_ids or
          v.dashboard_id in ^dashboard_ids or
          v.query_id in ^query_ids
    )
  end

  defp fetch_entities_by_ids(list) do
    # Group the results by entity type and fetch the full entities from the
    # database. Every entity is then represented as a map with the entity as
    # value and its type as a key. This is required as the GraphQL API needs to
    # match every different type to a GraphQL type. The end result is a list
    # like [%{project_watchlist: w}, %{insight: i}, %{chart_configuration: c},
    # %{screener: s}, %{address_watchlist: a}]
    list
    |> Enum.group_by(&String.to_existing_atom(&1.entity_type), & &1.entity_id)
    |> Enum.flat_map(fn {type, ids} ->
      entity_module = deduce_entity_module(type)

      {:ok, data} = entity_module.by_ids(ids, [])

      Enum.map(data, fn entity ->
        %{type => transform_entity(entity)}
      end)
    end)
  end

  defp transform_entity(%{featured_item: featured_item} = entity) do
    # Populate the `is_featured` boolean value from the `featured_item` assoc
    is_featured = if featured_item, do: true, else: false

    %{entity | is_featured: is_featured}
  end

  defp transform_entity(entity) do
    entity
  end

  defp rewrite_keys(list) do
    Enum.map(list, fn elem ->
      case Map.to_list(elem) do
        # Check if the watchlist is a screener so we can rewrite its name.
        # Screeners are watchlists so in the votes table their votes are stored
        # in the watchlist_id column
        [{:watchlist, watchlist}] ->
          case {UserList.screener?(watchlist), UserList.type(watchlist)} do
            {true, _type} ->
              %{screener: watchlist}

            {false, :project} ->
              %{project_watchlist: watchlist}

            {false, :blockchain_address} ->
              %{address_watchlist: watchlist}
          end

        # Check if the argument is in the right format. If this was a catch-all
        # case then wrong arugment types would still be passed through here
        # without any changes.
        [{type, entity}] when type in @supported_entity_type ->
          %{type => entity}
      end
    end)
  end

  # Which of the provided by the API opts are passed to the entity modules.

  @passed_opts [
    :filter,
    :cursor,
    :user_ids,
    :is_featured_data_only,
    :is_moderator,
    :min_title_length,
    :min_description_length
  ]

  defp entity_ids_query(:insight, opts) do
    # `ordered?: false` is important otherwise the default order will be applied
    # and this will conflict with the distinct(true) check
    entity_opts =
      Keyword.take(opts, @passed_opts) ++
        [preload?: false, distinct?: true, ordered?: false]

    current_user_id = Keyword.get(opts, :current_user_id)

    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} -> Post.public_entity_ids_query(entity_opts)
      {true, false} -> Post.user_entity_ids_query(current_user_id, entity_opts)
      {true, true} -> Post.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:user_trigger, opts) do
    # `ordered?: false` is important otherwise the default order will be applied
    # and this will conflict with the distinct(true) check
    entity_opts =
      Keyword.take(opts, @passed_opts) ++
        [preload?: false, distinct?: true, ordered?: false]

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} -> UserTrigger.public_entity_ids_query(entity_opts)
      {true, false} -> UserTrigger.user_entity_ids_query(current_user_id, entity_opts)
      {true, true} -> UserTrigger.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:screener, opts) do
    entity_opts = Keyword.take(opts, @passed_opts) ++ [is_screener: true]

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} -> UserList.public_entity_ids_query(entity_opts)
      {true, false} -> UserList.user_entity_ids_query(current_user_id, entity_opts)
      {true, true} -> UserList.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:project_watchlist, opts) do
    entity_opts = Keyword.take(opts, @passed_opts) ++ [is_screener: false, type: :project]

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} -> UserList.public_entity_ids_query(entity_opts)
      {true, false} -> UserList.user_entity_ids_query(current_user_id, entity_opts)
      {true, true} -> UserList.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:address_watchlist, opts) do
    entity_opts =
      Keyword.take(opts, @passed_opts) ++
        [is_screener: false, type: :blockchain_address]

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} -> UserList.public_entity_ids_query(entity_opts)
      {true, false} -> UserList.user_entity_ids_query(current_user_id, entity_opts)
      {true, true} -> UserList.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:chart_configuration, opts) do
    entity_opts = Keyword.take(opts, @passed_opts)

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} ->
        Chart.Configuration.public_entity_ids_query(entity_opts)

      {true, false} ->
        Chart.Configuration.user_entity_ids_query(current_user_id, entity_opts)

      {true, true} ->
        Chart.Configuration.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:dashboard, opts) do
    entity_opts = Keyword.take(opts, @passed_opts)

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} ->
        Dashboard.public_entity_ids_query(entity_opts)

      {true, false} ->
        Dashboard.user_entity_ids_query(current_user_id, entity_opts)

      {true, true} ->
        Dashboard.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp entity_ids_query(:query, opts) do
    entity_opts = Keyword.take(opts, @passed_opts)

    current_user_id = Keyword.get(opts, :current_user_id)
    include_current_user_entities = Keyword.fetch!(opts, :include_current_user_entities)
    include_public_entities = Keyword.fetch!(opts, :include_public_entities)

    case {include_current_user_entities, include_public_entities} do
      {false, true} ->
        Query.public_entity_ids_query(entity_opts)

      {true, false} ->
        Query.user_entity_ids_query(current_user_id, entity_opts)

      {true, true} ->
        Query.public_and_user_entity_ids_query(current_user_id, entity_opts)
    end
  end

  defp deduce_entity_creation_time_field(:insight), do: {:published_at, :inserted_at}
  defp deduce_entity_creation_time_field(_), do: {:inserted_at, :inserted_at}

  defp get_entity_votes_for_user(user_id) do
    from(v in Sanbase.Vote,
      where: v.user_id == ^user_id,
      distinct: true,
      select: %{
        entity_id: entity_id_selection(),
        entity_type: entity_type_selection()
      }
    )
    |> Sanbase.Repo.all()
  end

  defp update_opts(opts) do
    # TODO: Make it so it errors or combines the values
    # when user_role_data_only is provided
    opts =
      case Keyword.get(opts, :user_id_data_only) do
        user_id when is_integer(user_id) -> Keyword.put(opts, :user_ids, [user_id])
        _ -> opts
      end

    opts =
      case Keyword.get(opts, :filter) do
        %{slugs: slugs} = filter ->
          ids = Sanbase.Project.List.ids_by_slugs(slugs, [])
          filter = Map.put(filter, :project_ids, ids)
          Keyword.put(opts, :filter, filter)

        _ ->
          opts
      end

    opts =
      case Keyword.get(opts, :user_role_data_only) do
        :san_family ->
          user_ids = Sanbase.Accounts.Role.san_family_ids()
          Keyword.put(opts, :user_ids, user_ids)

        :san_team ->
          user_ids = Sanbase.Accounts.Role.san_team_ids()
          Keyword.put(opts, :user_ids, user_ids)

        _ ->
          opts
      end

    opts =
      case Keyword.get(opts, :current_user_data_only) do
        user_id when is_integer(user_id) ->
          opts
          |> Keyword.put(:include_current_user_entities, true)
          |> Keyword.put(:include_public_entities, false)

        _ ->
          opts
          |> Keyword.put(:include_current_user_entities, false)
          |> Keyword.put(:include_public_entities, true)
      end

    opts
  end
end
