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

  alias Sanbase.Entity.Registry
  alias Sanbase.Entity.Opts, as: EntityOpts
  alias Sanbase.Entity.Fetcher
  alias Sanbase.Insight.Post
  alias Sanbase.Chart
  alias Sanbase.Queries.Query
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Alert.UserTrigger

  @most_similar_max_results 20
  @default_similarity_threshold 0.4

  @type user_id :: non_neg_integer()
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
          | {:public_status, :all | :public | :private}

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

  @doc ~s"""
  Returns a map that shows if the entity is public, hidden and which user it belongs to.
  Using this then we can decide if any user has access to the entity.
  For example, if entity is private and belogns to user with id 1, user with id 2
  cannot access it.
  """
  @spec get_visibility_data(entity_type, entity_id) ::
          {:ok, Sanbase.Entity.Behaviour.visibility_map()} | {:error, String.t()}
  def get_visibility_data(entity_type, entity_id) do
    module = deduce_entity_module(entity_type)

    module.get_visibility_data(entity_id)
  end

  @doc ~s"""
  Return information about the number of created entities by a given user
  """
  @spec get_user_entities_stats(user_id) :: {:ok, map()} | no_return()
  def get_user_entities_stats(user_id) do
    with {:ok, query} <- by_user_id_base_query(user_id, []),
         result when is_list(result) <- Sanbase.Repo.all(query) do
      result = result |> Map.new(fn {type, count} -> {String.to_existing_atom(type), count} end)

      {:ok, result}
    end
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
  Get a list of the most similar entities of a given type or types based on
  semantic similarity using embeddings. The ordering is done by taking into
  consideration the similarity score for insights and creation time for other
  entity types.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  Requires `:ai_search_term` option to generate embeddings for similarity search.
  """
  @spec get_most_similar(entity_type | [entity_type], opts) ::
          {:ok, list(result_map)} | {:error, String.t()}
  def get_most_similar(type_or_types, opts) do
    case EntityOpts.put_new_embedding_opts(opts) do
      {:ok, opts} ->
        do_get_most_similar(List.wrap(type_or_types), opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc ~s"""
  Get the total count of similar entities of a given type or types.
  A cursor can be applied, but pagination cannot.

  ## Options

  See the ["Shared options"](#module-shared-options) section at the module
  documentation for more options.

  Requires `:ai_search_term` option to generate embeddings for similarity search.
  """
  @spec get_most_similar_total_count(entity_type | [entity_type], opts) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def get_most_similar_total_count(type_or_types, opts) do
    case EntityOpts.put_new_embedding_opts(opts) do
      {:ok, opts} ->
        do_get_most_similar_total_count(List.wrap(type_or_types), opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc ~s"""
  Map the entity type to the corresponding field in the votes table
  """
  def deduce_entity_vote_field(type), do: Registry.entity_vote_field(type)

  def deduce_entity_module(type), do: Registry.entity_module(type)

  def by_id(entity_type, entity_id) do
    module = deduce_entity_module(entity_type)
    module.by_id(entity_id, [])
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

  defdelegate extend_with_views_count(type_entity_list), to: Fetcher

  # Private functions

  defp do_get_most_recent_total_count(entities, opts) when is_list(entities) and entities != [] do
    opts = EntityOpts.update_opts(opts)
    {:ok, query} = most_recent_base_query(entities, opts)

    total_count =
      from(entity in subquery(query),
        select: fragment("COUNT(DISTINCT(?, ?))", entity.entity_id, entity.entity_type)
      )
      |> Sanbase.Repo.one()

    {:ok, total_count}
  end

  defp do_get_most_voted_total_count(entities, opts) when is_list(entities) and entities != [] do
    opts = EntityOpts.update_opts(opts)
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
    opts = EntityOpts.update_opts(opts)
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

    result = Fetcher.fetch_entities_by_ids(db_result)

    # Order the full list of entities by the creation time in descending order.
    # The end result is a list like: [%{project_watchlist: w}, %{insight: i},
    # %{chart_configuration: c}, %{screener: s}, %{address_watchlist: a}]
    sorted_result =
      Enum.sort_by(
        result,
        fn elem ->
          [{type, entity}] = Map.to_list(elem)

          {creation_time_field, creation_time_field_backup} =
            Registry.entity_creation_time_fields(type)

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
    opts = EntityOpts.update_opts(opts)
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
      |> Fetcher.fetch_entities_by_ids_preserve_order_rewrite_keys()

    {:ok, result}
  end

  defp do_get_most_used(entities, opts) when is_list(entities) and entities != [] do
    # The most used entities are the ones that the user has visited the most.

    # The get_most_used API is used (at the moment) only to get the querying user most
    # used entities. It should include both the public entities and the user's own
    # private entities. This is controlled by setting both `include_public_entities`
    # and `include_all_user_entities` to true
    opts = EntityOpts.update_opts(opts)

    query = most_used_base_query(entities, opts)

    result =
      Sanbase.Repo.all(query)
      |> Fetcher.fetch_entities_by_ids_preserve_order_rewrite_keys()

    {:ok, result}
  end

  defp do_get_most_used_total_count(entities, opts) when is_list(entities) and entities != [] do
    opts = EntityOpts.update_opts(opts)
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

  defp do_get_most_similar(entities, opts) when is_list(entities) and entities != [] do
    opts = EntityOpts.update_opts(opts)
    similarity_threshold = Keyword.get(opts, :similarity_threshold, @default_similarity_threshold)

    # For the paginated data query we want to limit the number of rows that the
    # expensive similarity subquery returns. Use a small internal cap here to
    # avoid fetching thousands of rows when we only need the top matches.
    opts = Keyword.put_new(opts, :limit, @most_similar_max_results)

    case most_similar_base_query(entities, opts) do
      {:ok, query} ->
        query =
          from(
            entity in subquery(query),
            order_by: [desc: entity.similarity, desc: entity.entity_id]
          )
          |> paginate(opts)

        db_result = Sanbase.Repo.all(query)
        result = Fetcher.fetch_entities_by_ids(db_result)
        pruned_result = Fetcher.prune_similarity_result(db_result, result, similarity_threshold)

        {:ok, pruned_result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_get_most_similar_total_count(entities, opts)
       when is_list(entities) and entities != [] do
    opts = EntityOpts.update_opts(opts)
    similarity_threshold = Keyword.get(opts, :similarity_threshold, @default_similarity_threshold)
    opts = Keyword.put_new(opts, :limit, @most_similar_max_results)

    case most_similar_base_query(entities, opts) do
      {:ok, query} ->
        query =
          from(
            entity in subquery(query),
            order_by: [desc: entity.similarity, desc: entity.entity_id]
          )

        db_result = Sanbase.Repo.all(query)
        result = Fetcher.fetch_entities_by_ids(db_result)
        pruned_result = Fetcher.prune_similarity_result(db_result, result, similarity_threshold)

        {:ok, length(pruned_result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp most_similar_base_query(entities, opts) when is_list(entities) and entities != [] do
    embedding = Keyword.fetch!(opts, :embedding)

    query =
      Enum.reduce(entities, nil, fn type, query_acc ->
        entity_ids_query = Registry.entity_ids_query(type, opts)

        entity_query =
          case type do
            :insight ->
              similarity_query =
                Post.similar_insights_query(embedding, entity_ids_query, opts)

              from(
                s in subquery(similarity_query),
                select: %{
                  entity_id: s.post_id,
                  entity_type: ^"insight",
                  similarity: s.similarity
                }
              )

            _ ->
              nil
          end

        case query_acc do
          nil ->
            entity_query

          query_acc ->
            if entity_query do
              query_acc |> union(^entity_query)
            else
              query_acc
            end
        end
      end)

    case query do
      nil ->
        {:error,
         "No supported entity types for similarity search. Only :insight is currently supported."}

      query ->
        {:ok, query}
    end
  end

  defp by_user_id_base_query(user_id, _opts) when is_integer(user_id) do
    entities = [
      :insight,
      :screener,
      :project_watchlist,
      :address_watchlist,
      :chart_configuration,
      :user_trigger,
      :dashboard,
      :query
    ]

    query =
      Enum.reduce(entities, nil, fn type, query_acc ->
        entity_ids_query =
          Registry.entity_ids_query(type,
            user_ids: [user_id],
            can_access_user_private_entities: true
          )

        entity_query =
          from(entity in entity_ids_query)
          # Remove the existing `entity.id` select and replace it with another
          # one
          |> exclude(:select)
          |> select([e], {^"#{type}", fragment("COUNT(*)")})

        case query_acc do
          nil ->
            entity_query

          query_acc ->
            query_acc |> union(^entity_query)
        end
      end)

    {:ok, query}
  end

  defp most_used_base_query(entities, opts) when is_list(entities) and entities != [] do
    user_id = Keyword.fetch!(opts, :current_user_id)

    # Craft the opts so it fetches all public entities and
    # all private entities of the user
    opts =
      opts
      |> Keyword.put(:user_ids_and_all_other_public, [user_id])
      |> Keyword.put(:can_access_user_private_entities, true)
      |> Keyword.put(:public_status, :all)

    query =
      Sanbase.Accounts.Interaction.get_user_most_used_query(user_id, entities, opts)

    where_clause_query =
      Enum.reduce(entities, nil, fn type, query_acc ->
        entity_ids_query = Registry.entity_ids_query(type, opts)
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
        entity_ids_query = Registry.entity_ids_query(type, opts)

        {creation_time_field, creation_time_field_backup} =
          Registry.entity_creation_time_fields(type)

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
        entity_ids_query = Registry.entity_ids_query(entity, opts)
        field = Registry.entity_vote_field(entity)

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
end
