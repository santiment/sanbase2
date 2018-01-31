defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config
  alias Sanbase.Etherbi.{Transactions, BurnRate, TransactionVolume}

  @doc ~S"""
    Return the token burn rate for the given ticker and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def burn_rate(_root, %{ticker: ticker, from: from, to: to, interval: interval}, _resolution) do
    with {:ok, burn_rates} <- BurnRate.Store.burn_rate(ticker, from, to, interval) do
      result =
        burn_rates
        |> Enum.map(fn {datetime, burn_rate} ->
          %{
            datetime: datetime,
            burn_rate: burn_rate |> Decimal.new()
          }
        end)

        {:ok, result}
    end
  end

  @doc ~S"""
    Return the transaction volume for the given ticker and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def transaction_volume(_root, %{ticker: ticker, from: from, to: to, interval: interval}, _resolution) do
    with {:ok, trx_volumes} <- TransactionVolume.Store.transaction_volume(ticker, from, to, interval) do
      result =
        trx_volumes
        |> Enum.map(fn {datetime, trx_volume} ->
          %{
            datetime: datetime,
            transaction_volume: trx_volume |> Decimal.new()
          }
        end)

        {:ok, result}
    end
  end

   @doc ~S"""
    Return the transactions that happend in or out of an exchange wallet for a given ticker
    and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def exchange_fund_flow(
        _root,
        %{
          ticker: ticker,
          from: from,
          to: to,
          transaction_type: transaction_type
        },
        _resolution
      ) do
    with {:ok, transactions} <- Transactions.Store.transactions(ticker, from, to, transaction_type) do
      result =
        transactions
        |> Enum.map(fn {datetime, volume, address} ->
          %{
            datetime: datetime,
            transaction_volume: volume |> Decimal.new(),
            address: address
          }
        end)

      {:ok, result}
    end
  end
end