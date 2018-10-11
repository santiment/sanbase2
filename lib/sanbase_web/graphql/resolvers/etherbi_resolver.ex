defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  alias Sanbase.Etherbi.{Transactions, BurnRate, TransactionVolume}
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeEthAddress}

  import Ecto.Query

  @doc ~S"""
    Return the token burn rate for the given ticker and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def burn_rate(_root, %{ticker: ticker, from: from, to: to, interval: interval}, _resolution) do
    with {:ok, contract_address, token_decimals} <- ticker_to_contract_info(ticker),
         {:ok, burn_rates} <- BurnRate.Store.burn_rate(contract_address, from, to, interval) do
      result =
        burn_rates
        |> Enum.map(fn {datetime, burn_rate} ->
          %{
            datetime: datetime,
            burn_rate: burn_rate / :math.pow(10, token_decimals)
          }
        end)

      {:ok, result}
    else
      _ -> {:error, "Can't fetch burn rate for #{ticker}"}
    end
  end

  @doc ~S"""
    Return the transaction volume for the given ticker and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def transaction_volume(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- ticker_to_contract_info(ticker),
         {:ok, trx_volumes} <-
           TransactionVolume.Store.transaction_volume(contract_address, from, to, interval) do
      result =
        trx_volumes
        |> Enum.map(fn {datetime, trx_volume} ->
          %{
            datetime: datetime,
            transaction_volume: trx_volume / :math.pow(10, token_decimals)
          }
        end)

      {:ok, result}
    else
      _ -> {:error, "Can't fetch transaction volume for #{ticker}"}
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
    with {:ok, contract_address, token_decimals} <- ticker_to_contract_info(ticker),
         {:ok, transactions} <-
           Transactions.Store.transactions(
             contract_address,
             from,
             to,
             transaction_type |> Atom.to_string()
           ) do
      result =
        transactions
        |> Enum.map(fn {datetime, volume, address} ->
          %{
            datetime: datetime,
            transaction_volume: volume / :math.pow(10, token_decimals),
            address: address
          }
        end)

      {:ok, result}
    else
      _ -> {:error, "Can't fetch the exchange funds for #{ticker}"}
    end
  end

  def exchange_wallets(_root, _args, _resolution) do
    {:ok, ExchangeEthAddress |> Repo.all()}
  end

  defp ticker_to_contract_info(ticker) do
    with project when not is_nil(project) <- get_project_by_ticker(ticker),
         initial_ico when not is_nil(initial_ico) <- Project.initial_ico(project),
         contract_address when not is_nil(contract_address) <- initial_ico.main_contract_address do
      {:ok, String.downcase(contract_address), project.token_decimals || 0}
    else
      _ -> {:error, "Can't find ticker contract address"}
    end
  end

  defp get_project_by_ticker(ticker) do
    Project
    |> where([p], p.ticker == ^ticker and not is_nil(p.coinmarketcap_id))
    |> Repo.one()
  end
end
