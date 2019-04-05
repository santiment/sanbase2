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
  @spec pipeline(Absinthe.Plug.Request.t()) :: Absinthe.Pipeline.t()
  def pipeline(%{pipeline: pipeline}) do
    pipeline
    |> Absinthe.Pipeline.insert_before(
      Absinthe.Phase.Document.Execution.Resolution,
      SanbseWeb.Graphql.Phase.Document.Execution.CacheDocument
    )
    |> Absinthe.Pipeline.insert_after(
      Absinthe.Phase.Document.Result,
      SanbseWeb.Graphql.Phase.Document.Execution.Idempotent
    )
  end

  @doc false
  @spec process(Absinthe.Plug.Request.Query.t(), Keyword.t()) ::
          Absinthe.DocumentProvider.result()
  def process(%{document: nil} = query, _), do: {:cont, query}
  def process(%{document: _} = query, _), do: {:halt, query}
end

defmodule SanbseWeb.Graphql.Phase.Document.Execution.CacheDocument do
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

  @compile inline: [add_cache_key_to_blueprint: 2]

  @spec run(Absinthe.Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(bp_root, _) do
    permissions = bp_root.execution.context.permissions

    cache_key =
      SanbaseWeb.Graphql.Cache.cache_key(
        {"bp_root", permissions},
        santize_blueprint(bp_root),
        ttl: 120,
        max_ttl_offset: 90
      )

    bp_root = add_cache_key_to_blueprint(bp_root, cache_key)

    case Cache.get(cache_key) do
      nil ->
        {:ok, bp_root}

      result ->
        {:jump, %{bp_root | result: result},
         SanbseWeb.Graphql.Phase.Document.Execution.Idempotent}
    end
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
  defp santize_blueprint(%DateTime{} = dt), do: dt
  defp santize_blueprint({:argument_data, _} = tuple), do: tuple
  defp santize_blueprint({a, b}), do: {a, santize_blueprint(b)}

  @cache_fields [:name, :argument_data, :selection_set, :selections, :fragments, :operations]
  defp santize_blueprint(map) when is_map(map) do
    Map.take(map, @cache_fields)
    |> Enum.map(&santize_blueprint/1)
    |> Map.new()
  end

  defp santize_blueprint(list) when is_list(list) do
    Enum.map(list, &santize_blueprint/1)
  end

  defp santize_blueprint(data), do: data
end

defmodule SanbseWeb.Graphql.Phase.Document.Execution.Idempotent do
  @moduledoc ~s"""
  A phase that does nothing and is inserted after the Absinthe's Result phase.
  `CacheDocument` phase jumps to this `Idempotent` phase if it finds the needed
  value in the cache so the Absinthe's Resolution and Result phases are skipped.
  """
  use Absinthe.Phase
  @spec run(Absinthe.Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(bp_root, _), do: {:ok, bp_root}
end
