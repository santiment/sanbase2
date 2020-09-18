defmodule SanbaseWeb.Graphql.Resolvers.ResearchResolver do
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]

  def uniswap_value_distribution(_root, _args, _res) do
    case Sanbase.Clickhouse.Research.Uniswap.value_distribution() do
      {:ok, distribution} ->
        {:ok, distribution}

      {:error, error} ->
        {:error, handle_graphql_error("Uniswap value distribution", "", error)}
    end
  end
end
