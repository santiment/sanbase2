defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeEthAddress}
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  alias Sanbase.Blockchain

  import SanbaseWeb.Graphql.Helpers.Async
  import Ecto.Query

  require Logger

  @doc ~S"""
    Return the token burn rate for the given slug and time period.
    Uses the influxdb cached values instead of issuing a GET request to etherbi
  """
  def burn_rate(_root, %{slug: slug, from: from, to: to, interval: interval} = args, _resolution) do
    with {:ok, contract_address, token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.BurnRate,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, burn_rates} <-
           Blockchain.BurnRate.burn_rate(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        burn_rates
        |> Utils.fit_from_datetime(args)

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
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TransactionVolume,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, trx_volumes} <-
           Blockchain.TransactionVolume.transaction_volume(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        trx_volumes
        |> Utils.fit_from_datetime(args)

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
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, _token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.DailyActiveAddresses,
             contract_address,
             from,
             to,
             interval,
             24 * 60 * 60,
             50
           ),
         {:ok, daily_active_addresses} <-
           Blockchain.DailyActiveAddresses.active_addresses(
             contract_address,
             from,
             to,
             interval
           ) do
      result =
        daily_active_addresses
        |> Utils.fit_from_datetime(args)

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
        } = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- slug_to_contract_info(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.ExchangeFundsFlow,
             contract_address,
             from,
             to,
             interval,
             60 * 60
           ),
         {:ok, exchange_funds_flow} <-
           Blockchain.ExchangeFundsFlow.transactions_in_out_difference(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        exchange_funds_flow
        |> Utils.fit_from_datetime(args)

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

  @doc ~S"""
    Return the average number of daily active addresses for a given slug and period of time
  """
  def average_daily_active_addresses(
        %Project{id: id} = project,
        %{from: from, to: to} = args,
        _resolution
      ) do
    async(
      Cache.func(
        fn -> calculate_average_daily_active_addresses(project, from, to) end,
        {:average_daily_active_addresses, id},
        args
      )
    )
  end

  def average_daily_active_addresses(
        %Project{id: id} = project,
        _args,
        _resolution
      ) do
    month_ago = Timex.shift(Timex.now(), days: -30)

    async(
      Cache.func(
        fn -> calculate_average_daily_active_addresses(project, month_ago, Timex.now()) end,
        {:average_daily_active_addresses, id}
      )
    )
  end

  def calculate_average_daily_active_addresses(project, from, to) do
    with {:ok, contract_address, _token_decimals} <- project_to_contract_info(project),
         {:ok, active_addresses} <-
           Blockchain.DailyActiveAddresses.active_addresses(contract_address, from, to) do
      {:ok, active_addresses}
    else
      error ->
        error_msg = "Can't fetch daily active addresses for #{project.coinmarketcap_id}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")

        {:ok, 0}
    end
  end

  defp slug_to_contract_info(slug) do
    with project when not is_nil(project) <- get_project_by_slug(slug),
         {:ok, contract_address, token_decimals} <- Utils.project_to_contract_info(project) do
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
