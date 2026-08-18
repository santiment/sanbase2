defmodule SanbaseWeb.Graphql.Phase.Document.Result.DataFetchErrors do
  @moduledoc ~s"""
  Injects soft data-fetch errors into the GraphQL response extensions.

  Dataloader batch failures that resolvers degraded gracefully (returning the
  old default value instead of failing the field) are recorded via
  `SanbaseWeb.Graphql.DataFetchErrors`. This phase runs right after Absinthe's
  Result phase and, when such errors exist, adds them to the response as
  `extensions.dataFetchErrors` so clients can tell "no data" apart from
  "fetch failed".

  The phase is skipped when a cached document result jumps to the Idempotent
  phase — recording a soft error sets `:do_not_cache_query`, so cached results
  never contain degraded data.
  """
  use Absinthe.Phase

  alias SanbaseWeb.Graphql.DataFetchErrors

  # Absinthe does not camelize extension keys (only document field names go
  # through the adapter), so the key is spelled in the camelCase the JSON
  # clients expect.
  @extensions_key :dataFetchErrors

  @spec run(Absinthe.Blueprint.t(), Keyword.t()) :: Absinthe.Phase.result_t()
  def run(bp_root, _) do
    case DataFetchErrors.get_unique() do
      [] ->
        {:ok, bp_root}

      errors ->
        result =
          Map.update(
            bp_root.result,
            :extensions,
            %{@extensions_key => errors},
            &Map.put(&1, @extensions_key, errors)
          )

        {:ok, %{bp_root | result: result}}
    end
  end
end
