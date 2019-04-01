defmodule SanbaseWeb.Graphql.DocumentProvider do
  @behaviour Absinthe.Plug.DocumentProvider

  import SanbaseWeb.Graphql.DocumentProvider.Utils, only: [cache_key_from_params: 2]

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

  defp cached_result(%{params: params, context: %{permissions: permissions}}) do
    cache_key_from_params(params, permissions)
    |> Cache.get()
  end
end

defmodule SanbseWeb.Graphql.Phase.Document.Execution.Resolution do
  use Absinthe.Phase

  alias Absinthe.{Blueprint, Phase}

  @cache_dict_key :graphql_cache_result

  @spec run(Blueprint.t(), Keyword.t()) :: Phase.result_t()
  def run(bp_root, options \\ []) do
    # Will be fetched from cache - that's what's saved by SanbaseWeb.Graphql.Absinthe.before_send
    result = Process.get(@cache_dict_key)

    {:ok, %{bp_root | result: result}}
  end
end
