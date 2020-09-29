defmodule SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver do
  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 3, handle_graphql_error: 4]

  import SanbaseWeb.Graphql.Helpers.CalibrateInterval, only: [calibrate: 7]

  alias Sanbase.Clickhouse.HistoricalBalance

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 300

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
        %{selector: selector, from: from, to: to, interval: interval, address: address},
        _resolution
      ) do
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

  def historical_balance(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, address: address},
        _resolution
      ) do
    HistoricalBalance.historical_balance(
      %{infrastructure: "ETH", slug: slug},
      address,
      from,
      to,
      interval
    )
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error("Historical Balances", slug, error)
    end)
  end

  def address_historical_balance_change(
        _root,
        %{selector: selector, from: from, to: to, addresses: addresses},
        _resolution
      ) do
    HistoricalBalance.balance_change(
      selector,
      addresses,
      from,
      to
    )
    |> case do
      {:ok, data} ->
        data =
          Enum.map(data, fn {address, {balance_start, balance_end, balance_change}} ->
            %{
              address: address,
              balance_start: balance_start,
              balance_end: balance_end,
              balance_change_amount: balance_change,
              balance_change_percent: Sanbase.Math.percent_change(balance_start, balance_end)
            }
          end)

        {:ok, data}

      {:error, error} ->
        {:error, error}
    end
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
          selector: %{slug: slug, infrastructure: "ETH"} = selector,
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
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate(
             HistoricalBalance.MinersBalance,
             slug,
             from,
             to,
             interval,
             86_400,
             @datapoints
           ),
         {:ok, balance} <-
           HistoricalBalance.MinersBalance.historical_balance(slug, from, to, interval) do
      {:ok, balance}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Miners Balance", slug, error)}
    end
  end
end
