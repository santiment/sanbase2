defmodule SanbaseWeb.Graphql.Resolvers.ExchangeResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 3]

  alias Sanbase.Clickhouse.ExchangeAddress
  alias Sanbase.Clickhouse.Exchanges

  @doc ~s"List all exchanges"
  def all_exchanges(_root, %{slug: slug} = args, _resolution) do
    ExchangeAddress.exchange_names(slug, Map.get(args, :is_dex, nil))
  end

  def top_exchanges_by_balance(
        _root,
        args,
        _resolution
      ) do
    limit = Map.get(args, :limit, 100)

    opts =
      case Map.split(args, [:owner, :label]) do
        {map, _rest} when map_size(map) > 0 -> [additional_filters: Keyword.new(map)]
        _ -> []
      end

    with {:ok, selector} <- Sanbase.Project.Selector.args_to_selector(args),
         {:ok, result} <- Exchanges.ExchangeMetric.top_exchanges_by_balance(selector, limit, opts) do
      {:ok, result}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Top Exchanges By Balance",
        Sanbase.Project.Selector.args_to_raw_selector(args),
        error
      )
    end)
  end
end
