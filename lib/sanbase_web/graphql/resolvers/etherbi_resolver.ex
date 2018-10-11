defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  alias Sanbase.Etherbi.{Transactions, BurnRate, TransactionVolume, DailyActiveAddresses}
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeEthAddress}
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  import Absinthe.Resolution.Helpers
  import Ecto.Query

  require Logger

  @doc ~S"""
    Return the token burn rate for the given slug and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def burn_rate(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with {:ok, contract_address, token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             BurnRate.Store,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
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
      error ->
        error_msg = "Can't fetch burn rate for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
    Return the transaction volume for the given slug and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def transaction_volume(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             TransactionVolume.Store,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
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
      error ->
        error_msg = "Can't fetch transaction for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
    Return the number of daily active addresses for a given slug
  """
  def daily_active_addresses(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract_address, _token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             DailyActiveAddresses.Store,
             contract_address,
             from,
             to,
             interval,
             24 * 60 * 60,
             50
           ),
         {:ok, daily_active_addresses} <-
           DailyActiveAddresses.Store.daily_active_addresses(contract_address, from, to, interval) do
      result =
        daily_active_addresses
        |> Enum.map(fn [datetime, active_addresses] ->
          %{
            datetime: datetime,
            active_addresses: active_addresses |> round() |> trunc()
          }
        end)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch daily active addresses for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
    Return the transactions that happend in or out of an exchange wallet for a given slug
    and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def exchange_funds_flow(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval
        },
        _resolution
      ) do
    with {:ok, contract_address, _token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Transactions.Store,
             contract_address,
             from,
             to,
             interval,
             60 * 60
           ),
         {:ok, funds_flow_list} <-
           Transactions.Store.transactions_in_out_difference(
             contract_address,
             from,
             to,
             interval
           ) do
      result =
        funds_flow_list
        |> Enum.map(fn {datetime, funds_flow} ->
          %{
            datetime: datetime,
            funds_flow: funds_flow
          }
        end)

      {:ok, result}
    else
      error ->
        error_msg = "Can't fetch the exchange fund flow for #{slug}."
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def exchange_wallets(_root, _args, _resolution) do
    {:ok, ExchangeEthAddress |> Repo.all()}
  end

  defp ticker_to_contract_info(ticker) do
    with project when not is_nil(project) <- get_project_by_ticker(ticker),
         contract_address when not is_nil(contract_address) <- project.main_contract_address do
      {:ok, String.downcase(contract_address), project.token_decimals || 0}
    else
      _ -> {:error, "Can't find contract address of #{project.coinmarketcap_id}"}
    end
  end

  defp ticker_to_contract_info(ticker) do
    with project when not is_nil(project) <- get_project_by_ticker(ticker),
         {:ok, contract_address, token_decimals} <- project_to_contract_info(project) do
      {:ok, contract_address, token_decimals}
    else
      _ -> {:error, "Can't find contract address for #{slug}"}
    end
  end

  defp get_project_by_slug(slug) do
    Project
    |> where([p], p.coinmarketcap_id == ^slug)
    |> Repo.one()
  end
end
