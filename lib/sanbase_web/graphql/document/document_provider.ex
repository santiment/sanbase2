defmodule SanbaseWeb.Graphql.DocumentProvider do
  @moduledoc ~s"""
  Custom Absinthe DocumentProvider for more effective caching.

  The `ContextPlug` runs before this DocumentProvider. In this plug the context is
  created. It checks the Authorization header and adds the user, permissions and cache key
  to the context. The cahce key is calculated from the  `params` (the full `query`
  and `variables`).

  Absinthe phases have one main difference compared to plugs - all phases must run
  and cannot be halted. Therefore to be able to skip some phases, the pipeline
  definition must exclude this. This is exactly how this document provider works.
  If the value is present in the cache, then from the pipeline the `Resolution` and
  `Result` phases are deleted in favor of a custom phase that puts the result in the
  Blueprint.
  If the value is not present in the cache, the pipeline is not modified and the
  `Resolution` and `Result` phases run as expected. After that a `before_send` hook
  persists the result in the cache.

  If the value is present in the cache it is copied to the Process dictionary.
  Copying the value to the Process dictionary avoids issues when the cache expires
  after it is checked but before the value is retrieved when sending it.

  The whole Absinthe request is executed in a single process so all phases can use
  the same Process dictionary.
  """
  @behaviour Absinthe.Plug.DocumentProvider

  alias SanbaseWeb.Graphql.Cache

  @cache_dict_key :graphql_cache_result

  @doc false
  @spec pipeline(Absinthe.Plug.Request.t()) :: Absinthe.Pipeline.t()
  def pipeline(%{pipeline: pipeline} = query) do
    case cached_result(query) do
      nil ->
        pipeline

      result ->
        # Store it in the process dictionary as the cache key could expire
        # before the phase that get's it from the cache is reached
        Process.put(@cache_dict_key, result)

        pipeline
        |> Absinthe.Pipeline.replace(
          Absinthe.Phase.Document.Execution.Resolution,
          SanbseWeb.Graphql.Phase.Document.Execution.Resolution
        )
        |> Absinthe.Pipeline.without(Absinthe.Phase.Document.Result)
    end
  end

  @doc false
  @spec process(Absinthe.Plug.Request.Query.t(), Keyword.t()) ::
          Absinthe.DocumentProvider.result()
  def process(%{document: nil} = query, _),
    do: {:cont, query}

  def process(%{document: _} = query, _),
    do: {:halt, query}

  defp cached_result(%{context: %{query_cache_key: cache_key}}) do
    cache_key
    |> Cache.get()
  end
end

defmodule SanbseWeb.Graphql.Phase.Document.Execution.Resolution do
  use Absinthe.Phase

  alias Absinthe.{Blueprint, Phase}

  @cache_dict_key :graphql_cache_result

  @spec run(Blueprint.t(), Keyword.t()) :: Phase.result_t()
  def run(bp_root, _) do
    # Will be fetched from cache - that's what's saved by SanbaseWeb.Graphql.Absinthe.before_send
    result = Process.get(@cache_dict_key)

    {:ok, %{bp_root | result: result}}
  end
end
