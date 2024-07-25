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

  def get_label_based_metric_owners(_root, %{metric: metric} = args, _resolution) do
    Exchanges.owners_by_slug_and_metric(metric, args[:slug])
  end

  def top_exchanges_by_balance(
        _root,
        args,
        _resolution
      ) do
    limit = Map.get(args, :limit, 10)

    with true <- validate_top_exchanges_slug(args),
         {:ok, result} <- Exchanges.top_exchanges_by_balance(%{slug: args.slug}, limit) do
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

  defp validate_top_exchanges_slug(%{selector: _}),
    do: {:error, "The `selector` parameter has been deprecated. Please provide just `slug`"}

  defp validate_top_exchanges_slug(%{slug: slug}) when is_binary(slug), do: true
  defp validate_top_exchanges_slug(%{}), do: {:error, "Please provei the `slug` parameter"}
end
