defmodule SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver do
  import Sanbase.Utils.ErrorHandling,
    only: [maybe_handle_graphql_error: 2, handle_graphql_error: 3, handle_graphql_error: 4]

  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 7]

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

  def miners_balance(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(
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
