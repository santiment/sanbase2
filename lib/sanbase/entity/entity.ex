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
          optional(:screener) => %Sanbase.UserList{},
          optional(:project_watchlist) => %Sanbase.UserList{},
          optional(:address_watchlist) => %Sanbase.UserList{},
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
    case Registry.fetch_entity_module(entity_type) do
      {:ok, module} -> module.get_visibility_data(entity_id)
      :error -> {:error, "Unknown entity type: #{inspect(entity_type)}"}
    end
  end

  @doc """
  Maps the vote-API entity name to the Entity-API type.
  The Vote schema uses `:post` (column `post_id`) while the Entity API
  exposes the same entity as `:insight`. Other types are identical.
  """
  def vote_entity_to_entity_type(:post), do: :insight
  def vote_entity_to_entity_type(other), do: other

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

  def extend_with_views_count(type_entity_list),
    do: Fetcher.extend_with_views_count(type_entity_list)

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

    # Every user's vote is on its own row, so counting rows counts voters. The transformed
    # row takes a DISTINCT before COUNT, so every entity is counted once.
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

    # The base query gives every type a creation time field under the same name, so the
    # results can be sorted before limit and offset are applied.
    query =
      from(
        entity in subquery(query),
        order_by: [desc: entity.creation_time, desc: entity.entity_id]
      )
      |> paginate(opts)

    db_result = Sanbase.Repo.all(query)

    result =
      db_result
      |> Fetcher.fetch_entities_by_ids()
      |> Fetcher.rewrite_keys()

    # Newest first. Result looks like [%{project_watchlist: w}, %{insight: i}, ...]
    sorted_result =
      Enum.sort_by(
        result,
        fn elem ->
          [{type, entity}] = Map.to_list(elem)

          {creation_time_field, creation_time_field_backup} =
            Registry.entity_creation_time_fields(type)

          # The fields are the same for every type except insights: a user's own drafts
          # have no :published_at, so :inserted_at is used instead.
          creation_time =
            Map.get(entity, creation_time_field) || Map.get(entity, creation_time_field_backup)

          creation_time_unix =
            DateTime.from_naive!(creation_time, "Etc/UTC") |> DateTime.to_unix()

          # Unix timestamps so the tuples compare. The id is the second element, so a tie
          # puts the higher id (created later) first.
          {creation_time_unix, Map.get(entity, :id)}
        end,
        :desc
      )

    {:ok, sorted_result}
  end

  defp do_get_most_voted(entities, opts) when is_list(entities) and entities != [] do
    opts = EntityOpts.update_opts(opts)
    {:ok, query} = most_voted_base_query(entities, opts)

    # The group by counts the votes per entity. Exactly one entity id per row is non-null,
    # so the group by expression works as intended.
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
      |> order_by([v], desc: coalesce(sum(v.count), 0))

    # All known types are listed. The unwanted ones are already excluded by the where
    # clause above and never match the case statement.
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

    # It serves only the querying user's own most-used entities, which include their
    # private ones - hence both flags are true.
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

    # A small internal cap on the expensive similarity subquery - only the top matches
    # are needed, not thousands of rows.
    opts = Keyword.put_new(opts, :limit, @most_similar_max_results)

    case most_similar_base_query(entities, opts) do
      {:ok, query} ->
        query =
          from(
            entity in subquery(query),
            order_by: [desc: entity.similarity, desc: entity.entity_id]
          )
          |> paginate(opts)

        db_result = Sanbase.Repo.VectorQuery.all(query)
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

        db_result = Sanbase.Repo.VectorQuery.all(query)
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

        cond do
          not is_nil(entity_query) and not is_nil(query_acc) ->
            query_acc |> union(^entity_query)

          is_nil(query_acc) and not is_nil(entity_query) ->
            entity_query

          is_nil(entity_query) and not is_nil(query_acc) ->
            query_acc

          true ->
            nil
        end
      end)

    case query do
      nil ->
        {:error,
         "No supported entity types for similarity search. Only :insight is currently supported."}

      query ->
        query = maybe_filter_current_user_voted_for_only(query, opts, :entity)
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

    query
    |> where(^where_clause_query)
  end

  defp most_recent_base_query(entities, opts) when is_list(entities) and entities != [] do
    # The most recent entity could be private, so look only at public ones. Fetching the
    # user's own entities changes the filter to their creations only.

    # One query per type returning {entity id, entity type, creation time}. They share
    # field names (inserted_at/published_at are renamed) so a UNION can combine them,
    # which is required as the data comes from tables with different schemas.
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
            # The fields are the same for every type except insights: a user's own
            # insights can be drafts, which have no :published_at, so :inserted_at is
            # used instead.
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

    query = maybe_filter_current_user_voted_for_only(query, opts, :entity)

    {:ok, query}
  end

  defp most_voted_base_query(entities, opts) when is_list(entities) and entities != [] do
    # The most voted entity could have been made private after its votes, so look only at
    # public ones. Fetching the user's own entities changes the filter to their creations.

    # The ids come from the votes table, where every type has its own <type>_id column.
    query = from(vote in Sanbase.Vote)

    # One where clause per type, OR-ed, keeping the rows whose id is in that type's
    # subquery. Watchlists and screeners share the watchlist_id column, but their
    # subqueries are disjoint.
    query =
      Enum.reduce(entities, query, fn entity, query_acc ->
        entity_ids_query = Registry.entity_ids_query(entity, opts)
        field = Registry.entity_vote_field(entity)

        query_acc
        |> or_where([v], field(v, ^field) in subquery(entity_ids_query))
      end)

    query = maybe_filter_current_user_voted_for_only(query, opts, :vote)

    {:ok, query}
  end

  defp maybe_filter_current_user_voted_for_only(query, opts, :vote) do
    case Keyword.get(opts, :current_user_voted_for_only) do
      user_id when is_integer(user_id) ->
        # `query` is on top of Sanbase.Vote, so its fields are post_id, watchlist_id, ...
        filter_user_voted_for_entities(query, user_id)

      _ ->
        query
    end
  end

  defp maybe_filter_current_user_voted_for_only(query, opts, :entity) do
    case Keyword.get(opts, :current_user_voted_for_only) do
      user_id when is_integer(user_id) ->
        # `query` has `entity_id` and `entity_type` fields to filter on.
        filter_entity_query_to_user_voted_only(query, user_id)

      _ ->
        query
    end
  end

  defp filter_user_voted_for_entities(query, user_id) do
    # Entities the user has voted for. All votes (1 to 20) live on one row in the `count`
    # column, so no `distinct` is needed. A `where: vote.user_id == ^user_id` would count
    # only that user's votes, making "sort by most voted first" impossible.
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

  defp filter_entity_query_to_user_voted_only(query, user_id) do
    user_voted_subquery =
      from(v in Sanbase.Vote,
        where: v.user_id == ^user_id,
        distinct: true,
        select: %{entity_id: entity_id_selection(), entity_type: entity_type_selection()}
      )

    from(row in subquery(query),
      join: v in subquery(user_voted_subquery),
      on: row.entity_id == v.entity_id and row.entity_type == v.entity_type
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
