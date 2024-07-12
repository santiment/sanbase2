defmodule SanbaseWeb.Graphql.DocumentProvider do
  @moduledoc ~s"""
  Custom Absinthe DocumentProvider for more effective caching.

  Absinthe phases have one main difference compared to plugs - all phases must run
  and cannot be halted. But phases can be jumped over by returning
  `{:jump, result, destination_phase}`

  This module makes use of 2 new phases - a `CacheDocument` phase and `Idempotent`
  phase.

  If the value is present in the cache it is put in the blueprint and the execution
  jumps to the Idempotent phase, effectively skipping the Absinthe's Resolution
  and Result phases. Result is the last phase in the pipeline so the Idempotent
  phase is inserted after it.

  If the value is not present in the cache, the Absinthe's default Resolution and
  Result phases are being executed and the new DocumentCache and Idempotent phases
  are doing nothing.

  In the end there's a `before_send` hook that adds the result into the cache.
  """
  @behaviour Absinthe.Plug.DocumentProvider

  alias SanbaseWeb.Graphql.Cache

  @doc false
  @impl true
  def pipeline(%Absinthe.Plug.Request.Query{pipeline: pipeline}) do
    pipeline
    |> Absinthe.Pipeline.insert_before(
      Absinthe.Phase.Document.Complexity.Analysis,
      SanbaseWeb.Graphql.Phase.Document.Complexity.Preprocess
    )
    |> Absinthe.Pipeline.insert_before(
      Absinthe.Phase.Document.Execution.Resolution,
      SanbaseWeb.Graphql.Phase.Document.Execution.CacheDocument
    )
    |> Absinthe.Pipeline.insert_after(
      Absinthe.Phase.Document.Result,
      SanbaseWeb.Graphql.Phase.Document.Execution.Idempotent
    )
  end

  @doc false
  @impl true
  def process(%Absinthe.Plug.Request.Query{document: nil} = query, _), do: {:cont, query}
  def process(%Absinthe.Plug.Request.Query{document: _} = query, _), do: {:halt, query}
end

defmodule SanbaseWeb.Graphql.Phase.Document.Execution.CacheDocument do
  @moduledoc ~s"""
  Custom phase for obtaining the result from cache.
  In case the value is not present in the cache, the default Resolution and Result
  phases are ran. Otherwise the custom Resolution phase is ran and Result is jumped
  over.

  When calculating the cache key only some of the fields in the whole blueprint are
  taken into account. They are defined in the module attribute @cache_fields
  The only values that are converted to something else during constructing
  of the cache key are:
  - DateTime - It is rounded by TTL so all datetiems in a range yield the same cache key
  - Struct - All structs are converted to plain maps
  """
  use Absinthe.Phase

  alias SanbaseWeb.Graphql.Cache
  @compile inline: [add_cache_key_to_blueprint: 2, queries_in_request: 1]

  @cached_queries SanbaseWeb.Graphql.AbsintheBeforeSend.cached_queries()

  @spec run(Absinthe.Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(bp_root, _) do
    queries_in_request = queries_in_request(bp_root)

    case Enum.any?(queries_in_request, &(&1 in @cached_queries)) do
      false ->
        {:ok, bp_root}

      true ->
        context = bp_root.execution.context

        # Add keys that can affect the data the user can have access to
        additional_keys_hash =
          {context.permissions, context.requested_product_id, context.auth.subscription,
           context.auth.plan, context.auth.auth_method}
          |> Sanbase.Cache.hash()

        # The ttl/max_ttl_offset might be rewritten in case `caching_params`
        # are provided. The rewriting happens in the absinthe before_send function
        cache_key =
          SanbaseWeb.Graphql.Cache.cache_key(
            {"bp_root", additional_keys_hash},
            sanitize_blueprint(bp_root),
            ttl: 30,
            max_ttl_offset: 30
          )

        bp_root = add_cache_key_to_blueprint(bp_root, cache_key)

        case Cache.get(cache_key) do
          nil ->
            {:ok, bp_root}

          result ->
            # Storing it again `touch`es it and the TTL timer is restarted.
            # This can lead to infinite storing the same value
            Process.put(:do_not_cache_query, true)

            {:jump, %{bp_root | result: result},
             SanbaseWeb.Graphql.Phase.Document.Execution.Idempotent}
        end
    end
  end

  # Private functions

  defp queries_in_request(%{operations: operations}) do
    operations
    |> Enum.flat_map(fn %{selections: selections} ->
      selections
      |> Enum.map(fn %{name: name} -> Inflex.camelize(name, :lower) end)
    end)
  end

  defp add_cache_key_to_blueprint(
         %{execution: %{context: context} = execution} = blueprint,
         cache_key
       ) do
    %{
      blueprint
      | execution: %{execution | context: Map.put(context, :query_cache_key, cache_key)}
    }
  end

  # Leave only the fields that are needed to generate the cache key
  # This let's us cache with values that are interpolated into the query string itself
  # The datetimes are rounded so all datetimes in a bucket generate the same
  # cache key
  defp sanitize_blueprint(%DateTime{} = dt), do: dt

  defp sanitize_blueprint(
         {:argument_data, %{function: %{"args" => %{"baseProjects" => base_projects}}}} = tuple
       ) do
    has_watchlist_base? =
      Enum.any?(base_projects, fn elem ->
        match?(%{"watchlistId" => _}, elem) or match?(%{"watchlistSlug" => _}, elem)
      end)

    has_watchlist_base? && Process.put(:do_not_cache_query, true)

    tuple
  end

  defp sanitize_blueprint({:argument_data, _} = tuple), do: tuple

  defp sanitize_blueprint({a, b}), do: {a, sanitize_blueprint(b)}

  @cache_fields [
    :name,
    :argument_data,
    :selection_set,
    :selections,
    :fragments,
    :operations,
    :alias
  ]
  defp sanitize_blueprint(map) when is_map(map) do
    Map.take(map, @cache_fields)
    |> Enum.map(&sanitize_blueprint/1)
    |> Map.new()
  end

  defp sanitize_blueprint(list) when is_list(list) do
    Enum.map(list, &sanitize_blueprint/1)
  end

  defp sanitize_blueprint(data), do: data
end

defmodule SanbaseWeb.Graphql.Phase.Document.Execution.Idempotent do
  @moduledoc ~s"""
  A phase that does nothing and is inserted after the Absinthe's Result phase.
  `CacheDocument` phase jumps to this `Idempotent` phase if it finds the needed
  value in the cache so the Absinthe's Resolution and Result phases are skipped.
  """
  use Absinthe.Phase
  @spec run(Absinthe.Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(bp_root, _), do: {:ok, bp_root}
end

defmodule SanbaseWeb.Graphql.Phase.Document.Complexity.Preprocess do
  use Absinthe.Phase
  @spec run(Absinthe.Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(bp_root, _) do
    metrics =
      bp_root.operations
      |> Enum.flat_map(fn %{selections: selections} ->
        selections_to_metrics(selections)
      end)

    case metrics do
      [_ | _] = metrics -> Process.put(:__metric_name_from_get_metric_api__, metrics)
      _ -> :ok
    end

    {:ok, bp_root}
  end

  defp selections_to_metrics(selections) do
    selections
    |> Enum.flat_map(fn
      %{name: name, argument_data: %{metric: metric}} = struct ->
        case Inflex.underscore(name) do
          "get_metric" ->
            get_metric_selections_to_metrics(struct.selections, metric)

          _ ->
            []
        end

      _ ->
        []
    end)
  end

  defp get_metric_selections_to_metrics(selections, metric) do
    selections =
      Enum.map(selections, fn
        %{name: name} -> name |> Inflex.underscore()
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    # Put the metric name in the list 0, 1 or 2 times, depending
    # on the selections. `timeseries_data` and `aggregated_timeseries_data`
    # would go through the complexity code once, remioing the metric
    # name from the list both times - so it has to be there twice, while
    # `timeseries_data_complexity` won't go through that path.
    # `histogram_data` does not have complexity checks right now.

    temp = selections -- ["timeseries_data", "aggregated_timeseries_data"]
    common_parts = selections -- temp
    Enum.map(common_parts, fn _ -> metric end)
  end
end
