defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeAddress}
  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.Blockchain

  alias SanbaseWeb.Graphql.SanbaseDataloader

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
           Blockchain.DailyActiveAddresses.average_active_addresses(
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
      {:error, {:missing_contract, error_msg}} ->
        {:error, error_msg}

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
             60 * 60 * 24,
             90
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

  @doc ~s"""
  Returns the token velocity for a given slug and time period.
  """
  def token_velocity(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Blockchain.TokenVelocity,
             contract_address,
             from,
             to,
             interval,
             60 * 60 * 24,
             90
           ),
         {:ok, token_velocity} <-
           Blockchain.TokenVelocity.token_velocity(
             contract_address,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_velocity |> Utils.fit_from_datetime(args)}
    else
      {:error, error} ->
        error_msg = "Can't fetch token velocity for #{slug}."
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
        %Project{} = project,
        args,
        %{context: %{loader: loader}}
      ) do
    to = Map.get(args, :to, Timex.now())
    from = Map.get(args, :from, Timex.shift(to, days: -30))

    loader
    |> Dataloader.load(SanbaseDataloader, :average_daily_active_addresses, %{
      project: project,
      from: from,
      to: to
    })
    |> on_load(&average_daily_active_addresses_on_load(&1, project))
  end

  def average_daily_active_addresses_on_load(loader, project) do
    with {:ok, contract_address, _token_decimals} <- Project.contract_info(project) do
      average_daily_active_addresses =
        loader
        |> Dataloader.get(
          SanbaseDataloader,
          :average_daily_active_addresses,
          contract_address
        )

      {:ok, average_daily_active_addresses || 0}
    else
      {:error, {:missing_contract, _}} ->
        {:ok, 0}

      {:error, error} ->
        error_msg = "Can't fetch average daily active addresses for #{Project.describe(project)}"
        Logger.warn(error_msg <> "Reason: #{inspect(error)}")

        {:ok, 0}
    end
  end
end
