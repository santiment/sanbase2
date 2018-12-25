defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeAddress}
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  alias Sanbase.Blockchain

  import SanbaseWeb.Graphql.Helpers.Async
  import Ecto.Query

  require Logger

  @doc ~S"""
  Return the token age consumed for the given slug and time period.
  """
  def token_age_consumed(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TokenAgeConsumed,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, token_age_consumed} <-
           Blockchain.TokenAgeConsumed.token_age_consumed(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        token_age_consumed
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      {:error, error} ->
        error_msg = "Can't fetch burn rate for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
  Return the average age of the tokens that were transacted for the given slug and time period.
  """
  def average_token_age_consumed_in_days(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TokenAgeConsumed,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, token_age} <-
           Blockchain.TokenAgeConsumed.average_token_age_consumed_in_days(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_age |> Utils.fit_from_datetime(args)}
    else
      {:error, error} ->
        error_msg = "Can't fetch average token age consumed in days for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
  Return the transaction volume for the given slug and time period.
  """
  def transaction_volume(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
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
      {:error, error} ->
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
    with {:ok, contract_address, _token_decimals} <- Project.contract_info_by_slug(slug),
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
      {:error, error} ->
        error_msg = "Can't fetch daily active addresses for #{slug}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
  Return the amount of tokens that were transacted in or out of an exchange wallet for a given slug
  and time period
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
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
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
      {:error, error} ->
        error_msg = "Can't fetch the exchange fund flow for #{slug}."
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~s"""
  Returns the token circulation for less than a day for a given slug and time period.
  """
  def token_circulation(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TokenCirculation,
             contract_address,
             from,
             to,
             interval,
             60 * 60,
             50
           ),
         {:ok, token_circulation} <-
           Blockchain.TokenCirculation.token_circulation(
             :less_than_a_day,
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      result =
        token_circulation
        |> Utils.fit_from_datetime(args)

      {:ok, result}
    else
      {:error, error} ->
        error_msg = "Can't fetch token circulation for #{slug}."
        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def exchange_wallets(_root, _args, _resolution) do
    {:ok, ExchangeAddress |> Repo.all() |> Repo.preload(:infrastructure)}
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
    with {:ok, contract_address, _token_decimals} <- Project.contract_info(project),
         {:ok, active_addresses} <-
           Blockchain.DailyActiveAddresses.active_addresses(contract_address, from, to) do
      {:ok, active_addresses}
    else
      {:error, error} ->
        error_msg = "Can't fetch daily active addresses for #{project.coinmarketcap_id}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")

        {:ok, 0}
    end
  end
end
