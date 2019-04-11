defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Helpers.Utils, only: [fit_from_datetime: 2, calibrate_interval: 7]

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, ExchangeAddress}

  alias Sanbase.Blockchain.{
    TokenVelocity,
    TokenCirculation,
    TokenAgeConsumed,
    TransactionVolume,
    DailyActiveAddresses,
    ExchangeFundsFlow
  }

  alias Sanbase.Clickhouse.Bitcoin
  alias SanbaseWeb.Graphql.SanbaseDataloader

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 50

  @doc ~S"""
  Return the token age consumed for the given slug and time period.
  """
  def token_age_consumed(
        _root,
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86400, @datapoints),
         {:ok, result} <- Bitcoin.token_age_consumed(from, to, interval) do
      result = Enum.map(result, fn elem -> Map.put(elem, :burn_rate, elem.token_age_consumed) end)
      {:ok, result}
    end
  end

  def token_age_consumed(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenAgeConsumed, contract, from, to, interval, 3600, @datapoints),
         {:ok, token_age_consumed} <-
           TokenAgeConsumed.token_age_consumed(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_age_consumed |> fit_from_datetime(args)}
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
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenAgeConsumed, contract, from, to, interval, 3600, @datapoints),
         {:ok, token_age} <-
           TokenAgeConsumed.average_token_age_consumed_in_days(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_age |> fit_from_datetime(args)}
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
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86400, @datapoints) do
      Bitcoin.transaction_volume(from, to, interval)
    end
  end

  def transaction_volume(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TransactionVolume, contract, from, to, interval, 3600, @datapoints),
         {:ok, trx_volumes} <-
           TransactionVolume.transaction_volume(contract, from, to, interval, token_decimals) do
      {:ok, trx_volumes |> fit_from_datetime(args)}
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
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86400, @datapoints) do
      Bitcoin.daily_active_addresses(from, to, interval)
    end
  end

  def daily_active_addresses(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, _token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(
             DailyActiveAddresses,
             contract,
             from,
             to,
             interval,
             86400,
             @datapoints
           ),
         {:ok, daily_active_addresses} <-
           DailyActiveAddresses.average_active_addresses(contract, from, to, interval) do
      {:ok, daily_active_addresses |> fit_from_datetime(args)}
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
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(ExchangeFundsFlow, contract, from, to, interval, 3600, @datapoints),
         {:ok, exchange_funds_flow} <-
           ExchangeFundsFlow.transactions_in_out_difference(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, exchange_funds_flow |> fit_from_datetime(args)}
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
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86400, @datapoints) do
      Bitcoin.token_circulation(from, to, interval)
    end
  end

  def token_circulation(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenCirculation, contract, from, to, interval, 86400, @datapoints),
         {:ok, token_circulation} <-
           TokenCirculation.token_circulation(
             :less_than_a_day,
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_circulation |> fit_from_datetime(args)}
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
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86400, @datapoints) do
      Bitcoin.token_velocity(from, to, interval)
    end
  end

  def token_velocity(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenVelocity, contract, from, to, interval, 86400, @datapoints),
         {:ok, token_velocity} <-
           TokenVelocity.token_velocity(contract, from, to, interval, token_decimals) do
      {:ok, token_velocity |> fit_from_datetime(args)}
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
    with {:ok, contract, _token_decimals} <- Project.contract_info(project) do
      average_daily_active_addresses =
        loader
        |> Dataloader.get(
          SanbaseDataloader,
          :average_daily_active_addresses,
          contract
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
