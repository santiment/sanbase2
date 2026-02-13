defmodule Sanbase.Entity.Fetcher do
  @moduledoc ~s"""
  Result fetching and post-processing for entity queries.

  Groups database results by type, fetches full entities from their
  respective modules, rewrites generic watchlist keys to specific types,
  and handles view count enrichment.
  """

  require Logger

  import Ecto.Query

  alias Sanbase.Entity.Registry
  alias Sanbase.UserList
  alias Sanbase.Accounts.Interaction

  @most_similar_max_results 20
  @most_similar_drop_off_threshold 0.2

  @doc """
  Groups db results by entity type, fetches full entities via their modules,
  and wraps each in a type-keyed map.
  """
  def fetch_entities_by_ids(list) do
    list
    |> Enum.group_by(&String.to_existing_atom(&1.entity_type), & &1.entity_id)
    |> Enum.flat_map(fn {type, ids} ->
      entity_module = Registry.entity_module(type)

      case entity_module.by_ids(ids, []) do
        {:ok, data} ->
          Enum.map(data, fn entity ->
            %{type => transform_entity(entity)}
          end)

        {:error, reason} ->
          Logger.warning("Failed to fetch #{type} entities: #{inspect(reason)}")
          []
      end
    end)
  end

  @doc """
  Fetches entities by ids while preserving the original ordering from db_result,
  then rewrites watchlist keys to their specific types.
  """
  def fetch_entities_by_ids_preserve_order_rewrite_keys(db_result) do
    # Record the position in the original result so we can restore order
    # after splitting into type groups for fetching.
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

    rewrite_keys(result)
  end

  @doc """
  Rewrites generic :watchlist keys to specific types (:screener,
  :project_watchlist, :address_watchlist) based on the watchlist properties.
  """
  def rewrite_keys(list) do
    Enum.map(list, fn elem ->
      case Map.to_list(elem) do
        [{:watchlist, watchlist}] ->
          case {UserList.screener?(watchlist), UserList.type(watchlist)} do
            {true, _type} ->
              %{screener: watchlist}

            {false, :project} ->
              %{project_watchlist: watchlist}

            {false, :blockchain_address} ->
              %{address_watchlist: watchlist}
          end

        [{type, entity}] ->
          %{type => entity}
      end
    end)
  end

  @doc """
  Filters similarity results by threshold and drop-off.
  """
  def prune_similarity_result(db_result, result, similarity_threshold) do
    similarity_map =
      db_result
      |> Enum.map(fn %{entity_id: entity_id, entity_type: entity_type, similarity: similarity} ->
        {{String.to_existing_atom(entity_type), entity_id}, similarity}
      end)
      |> Map.new()

    scored_result =
      Enum.map(result, fn elem ->
        [{type, entity}] = Map.to_list(elem)
        key = {type, entity.id}
        similarity = Map.get(similarity_map, key, 0.0)
        {elem, similarity}
      end)
      |> Enum.sort_by(fn {_elem, similarity} -> {0, similarity} end, :desc)
      |> Enum.filter(fn {_elem, similarity} -> similarity >= similarity_threshold end)
      |> Enum.take(@most_similar_max_results)

    case scored_result do
      [] ->
        []

      _ ->
        scored_result
        |> Enum.reduce({[], nil, 0}, fn
          {_elem, similarity}, {acc, prev_similarity, count}
          when prev_similarity != nil and
                 prev_similarity - similarity >= @most_similar_drop_off_threshold ->
            {acc, prev_similarity, count}

          {elem, similarity}, {acc, _prev_similarity, count} ->
            {[elem | acc], similarity, count + 1}
        end)
        |> then(fn {acc, _prev_similarity, _count} -> Enum.reverse(acc) end)
    end
  end

  @doc """
  Extends a list of type-entity maps with view counts from the Interaction table.
  """
  def extend_with_views_count(type_entity_list) do
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

  defp transform_entity(%{featured_item: featured_item} = entity) do
    is_featured = if featured_item, do: true, else: false
    %{entity | is_featured: is_featured}
  end

  defp transform_entity(entity), do: entity

  defp entity_views_query(type_entity_list) do
    entity_type_id_conditions = views_count_entity_type_id_conditions(type_entity_list)

    from(row in Interaction,
      where: ^entity_type_id_conditions,
      select: {row.entity_type, row.entity_id, fragment("COUNT(*)")},
      group_by: [row.entity_type, row.entity_id]
    )
  end

  defp views_count_entity_type_id_conditions(type_entity_list) do
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
end
