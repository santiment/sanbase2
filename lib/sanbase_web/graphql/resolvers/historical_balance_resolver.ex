defmodule SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver do
  import Absinthe.Resolution.Helpers

  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 4]

  alias Sanbase.Clickhouse.HistoricalBalance
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def assets_held_by_address(_root, args, _resolution) do
    selector =
      case Map.get(args, :selector) do
        nil -> %{infrastructure: "ETH", address: Map.fetch!(args, :address)}
        selector -> selector
      end

    HistoricalBalance.assets_held_by_address(selector)
    |> case do
      {:ok, result} ->
        # We do this, because many contracts emit a transfer
        # event when minting new tokens by setting 0x00...000
        # as the from address, hence 0x00...000 is "sending"
        # tokens it does not have which leads to "negative" balance

        result =
          result
          |> Enum.reject(fn %{balance: balance} -> balance < 0 end)

        {:ok, result}

      {:error, error} ->
        {:error,
         handle_graphql_error("Assets held by address", selector.address, error,
           description: "address"
         )}
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

  def transaction_volume_per_address(
        _root,
        %{
          selector: %{slug: slug} = selector,
          from: from,
          to: to,
          addresses: addresses
        },
        _resolution
      ) do
    with {:ok, contract, decimals} <- Sanbase.Model.Project.contract_info_by_slug(slug) do
      Sanbase.Clickhouse.Erc20Transfers.transaction_volume_per_address(
        addresses,
        contract,
        from,
        to,
        decimals
      )
      |> maybe_handle_graphql_error(fn error ->
        handle_graphql_error(
          "Historical Balance Change per Address",
          inspect(selector),
          error,
          description: "selector"
        )
      end)
    end
  end

  def transaction_volume_per_address(_root, _args, _resolution) do
    {:error,
     "Transaction volume per address is currently supported only for selectors with infrastructure ETH and a slug"}
  end

  def miners_balance(
        _root,
        %{} = args,
        _resolution
      ) do
    MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "miners_balance"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :balance)
  end

  def balance_usd(%{slug: slug, balance: balance}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :last_price_usd, slug)
    |> on_load(fn loader ->
      price_usd = Dataloader.get(loader, SanbaseDataloader, :last_price_usd, slug)

      {:ok, price_usd && balance * price_usd}
    end)
  end
end
