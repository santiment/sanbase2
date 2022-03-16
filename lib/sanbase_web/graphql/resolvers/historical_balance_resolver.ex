defmodule SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver do
  import Absinthe.Resolution.Helpers

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 4]

  alias Sanbase.Clickhouse.{HistoricalBalance, Balance}
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def assets_held_by_address(_root, args, _resolution) do
    selector = args_to_address_selector(args)

    case HistoricalBalance.assets_held_by_address(selector) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error,
         handle_graphql_error("Assets held by address", selector.address, error,
           description: "address"
         )}
    end
  end

  def usd_value_address_change(_root, args, _resolution) do
    selector = args_to_address_selector(args)

    case HistoricalBalance.usd_value_address_change(selector, args.datetime) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error,
         handle_graphql_error("Assets held by address", selector.address, error,
           description: "address"
         )}
    end
  end

  defp args_to_address_selector(args) do
    case Map.get(args, :selector) do
      nil ->
        address = args.address
        infrastructure = Sanbase.BlockchainAddress.to_infrastructure(address)
        %{infrastructure: infrastructure, address: address}

      selector ->
        selector
    end
  end

  def historical_balance(
        _root,
        %{from: from, to: to, interval: interval, address: address} = args,
        _resolution
      ) do
    selector =
      case args do
        %{selector: selector} -> selector
        %{slug: slug} -> %{slug: slug}
      end

    HistoricalBalance.historical_balance(
      selector,
      address,
      from,
      to,
      interval
    )
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Historical Balances",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def address_historical_balance_change(
        _root,
        %{selector: selector, from: from, to: to, addresses: addresses},
        _resolution
      ) do
    HistoricalBalance.balance_change(selector, addresses, from, to)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Historical Balance Change per Address",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def miners_balance(root, %{} = args, resolution) do
    MetricResolver.timeseries_data(
      root,
      args,
      Map.put(resolution, :source, %{metric: "miners_balance"})
    )
    |> Sanbase.Utils.Transform.rename_map_keys(
      old_key: :value,
      new_key: :balance
    )
  end

  def balance_usd(%{slug: slug, balance: balance}, _args, %{
        context: %{loader: loader}
      }) do
    loader
    |> Dataloader.load(SanbaseDataloader, :last_price_usd, slug)
    |> on_load(fn loader ->
      price_usd = Dataloader.get(loader, SanbaseDataloader, :last_price_usd, slug)

      {:ok, price_usd && balance * price_usd}
    end)
  end
end
