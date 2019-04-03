defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeAddress}
  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.Blockchain

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
end
