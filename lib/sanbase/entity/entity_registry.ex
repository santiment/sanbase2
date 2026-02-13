defmodule Sanbase.Entity.Registry do
  @moduledoc ~s"""
  Centralized registry of entity type metadata.

  Replaces scattered pattern-matched dispatch clauses in `Sanbase.Entity`
  with data-driven lookups. Adding a new entity type requires only adding
  an entry to the `@entities` map (plus implementing the Behaviour).
  """

  alias Sanbase.Chart
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Queries.Query
  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Alert.UserTrigger

  @entities %{
    insight: %{
      module: Post,
      vote_field: :post_id,
      creation_time: {:published_at, :inserted_at},
      base_ids_opts: [preload?: false, distinct?: true, ordered?: false]
    },
    # :watchlist is not a supported entity type in the public API, but it is
    # used internally. In the votes table and interaction table, screeners and
    # watchlists are stored under "watchlist". When fetching entities by IDs we
    # need to resolve :watchlist to UserList, then rewrite_keys distinguishes
    # the specific subtype (screener, project_watchlist, address_watchlist).
    watchlist: %{
      module: UserList,
      vote_field: :watchlist_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: []
    },
    user_trigger: %{
      module: UserTrigger,
      vote_field: :user_trigger_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: [preload?: false, distinct?: true, ordered?: false]
    },
    screener: %{
      module: UserList,
      vote_field: :watchlist_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: [is_screener: true]
    },
    project_watchlist: %{
      module: UserList,
      vote_field: :watchlist_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: [is_screener: false, type: :project]
    },
    address_watchlist: %{
      module: UserList,
      vote_field: :watchlist_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: [is_screener: false, type: :blockchain_address]
    },
    chart_configuration: %{
      module: Chart.Configuration,
      vote_field: :chart_configuration_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: []
    },
    dashboard: %{
      module: Dashboard,
      vote_field: :dashboard_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: []
    },
    query: %{
      module: Query,
      vote_field: :query_id,
      creation_time: {:inserted_at, :inserted_at},
      base_ids_opts: []
    }
  }

  # Additional vote field mappings for types that aren't full entity types
  # but need vote field lookup (e.g. :watchlist, :post, :timeline_event)
  # Additional vote field mappings for types that aren't in @entities
  # but need vote field lookup
  @extra_vote_fields %{
    post: :post_id,
    timeline_event: :timeline_event_id
  }

  @supported_entity_types [
    :insight,
    :watchlist,
    :screener,
    :chart_configuration,
    :user_trigger,
    :dashboard,
    :query
  ]

  # The list of opts passed through to entity modules
  @passed_opts [
    :filter,
    :cursor,
    :user_ids_and_all_other_public,
    :user_ids,
    :public_status,
    :can_access_user_private_entities,
    :is_featured_data_only,
    :is_moderator,
    :min_title_length,
    :min_description_length
  ]

  def supported_entity_types, do: @supported_entity_types

  @doc "Returns the config map for a given entity type. Raises if unknown."
  def get!(type) do
    Map.fetch!(@entities, type)
  end

  @doc "Returns the module for a given entity type."
  def entity_module(type) do
    case Map.fetch(@entities, type) do
      {:ok, %{module: module}} -> module
      :error -> raise ArgumentError, "Unknown entity type: #{inspect(type)}"
    end
  end

  @doc "Returns the vote table column for a given entity type."
  def entity_vote_field(type) do
    case Map.fetch(@entities, type) do
      {:ok, %{vote_field: field}} ->
        field

      :error ->
        case Map.fetch(@extra_vote_fields, type) do
          {:ok, field} -> field
          :error -> raise ArgumentError, "Unknown vote field for type: #{inspect(type)}"
        end
    end
  end

  @doc "Returns the {primary, fallback} creation time fields for a given entity type."
  def entity_creation_time_fields(type) do
    case Map.fetch(@entities, type) do
      {:ok, %{creation_time: fields}} -> fields
      :error -> {:inserted_at, :inserted_at}
    end
  end

  @doc "Builds the entity IDs query for a given type using the registry config."
  def entity_ids_query(type, opts) do
    config = get!(type)
    entity_opts = Keyword.take(opts, @passed_opts) ++ config.base_ids_opts

    entity_opts = maybe_add_insight_opts(type, entity_opts, opts)

    config.module.entity_ids_by_opts(entity_opts)
  end

  defp maybe_add_insight_opts(:insight, entity_opts, opts) do
    is_paywall_required =
      case get_in(opts, [:filter, :insight, :paywall]) do
        :paywalled_only -> true
        :non_paywalled_only -> false
        _ -> nil
      end

    entity_opts
    |> Keyword.put(:is_paywall_required, is_paywall_required)
    |> Keyword.put(:tags, get_in(opts, [:filter, :insight, :tags]))
  end

  defp maybe_add_insight_opts(_type, entity_opts, _opts), do: entity_opts
end
