defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils
  alias SanbaseWeb.Graphql.Helpers.Utils

  alias SanbaseWeb.Graphql.SanbaseDataloader

  import Absinthe.Resolution.Helpers

  alias Sanbase.Clickhouse.{
    DailyActiveAddresses,
    DailyActiveDeposits,
    GasUsed,
    HistoricalBalance,
    MiningPoolsDistribution,
    MVRV,
    NetworkGrowth,
    NVT,
    RealizedValue
  }

  @one_hour_seconds 3600

  def gas_used(
        _root,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    case GasUsed.gas_used(from, to, interval) do
      {:ok, gas_used} ->
        {:ok, gas_used}

      {:error, error} ->
        error_msg = "Can't calculate Gas used."
        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def network_growth(_root, args, _resolution) do
    interval = DateTimeUtils.compound_duration_to_seconds(args.interval)

    with {:ok, contract, _} <- Project.contract_info_by_slug(args.slug),
         {:ok, network_growth} <-
           NetworkGrowth.network_growth(contract, args.from, args.to, interval) do
      {:ok, network_growth}
    else
      error ->
        Logger.error("Can't calculate network growth. Reason: #{inspect(error)}")

        {:error, "Can't calculate network growth"}
    end
  end

  def mining_pools_distribution(
        _root,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    case MiningPoolsDistribution.distribution(from, to, interval) do
      {:ok, distribution} ->
        {:ok, distribution}

      {:error, error} ->
        error_msg = "Can't calculate mining pools distribution."
        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def mvrv_ratio(_root, args, _resolution) do
    # TODO: Check if interval is a whole day as in token circulation
    with {:ok, mvrv_ratio} <- MVRV.mvrv_ratio(args.slug, args.from, args.to, args.interval) do
      {:ok, mvrv_ratio}
    else
      {:error, error} ->
        Logger.warn(
          "Can't calculate MVRV ratio for project with coinmarketcap_id: #{args.slug}. Reason: #{
            inspect(error)
          }"
        )

        {:error, "Can't calculate MVRV ratio"}
    end
  end

  def daily_active_deposits(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract, _} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             DailyActiveDeposits,
             contract,
             from,
             to,
             interval,
             @one_hour_seconds,
             50
           ),
         {:ok, active_deposits} <-
           DailyActiveDeposits.active_deposits(contract, from, to, interval) do
      {:ok, active_deposits}
    else
      {:error, error} ->
        error_msg =
          "Can't calculate daily active deposits for project with coinmarketcap_id: #{slug}."

        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def daily_active_addresses(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract, _} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             DailyActiveAddresses,
             contract,
             from,
             to,
             interval,
             @one_hour_seconds,
             50
           ),
         {:ok, daily_active_addresses} <-
           DailyActiveAddresses.average_active_addresses(
             contract,
             from,
             to,
             interval
           ) do
      {:ok, daily_active_addresses}
    else
      {:error, {:missing_contract, error_msg}} ->
        {:error, error_msg}

      {:error, error} ->
        error_msg =
          "Can't calculate daily active addresses for project with coinmarketcap_id: #{slug}."

        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  @doc ~S"""
  Returns the average number of daily active addresses for the last 30 days
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

  defp average_daily_active_addresses_on_load(loader, project) do
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

  def realized_value(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    case RealizedValue.realized_value(slug, from, to, interval) do
      {:ok, realized_value} ->
        {:ok, realized_value}

      {:error, error} ->
        error_msg = "Can't calculate Realized Value for project with coinmarketcap_id: #{slug}."
        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def nvt_ratio(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, nvt_ratio} <- NVT.nvt_ratio(slug, from, to, interval) do
      {:ok, nvt_ratio}
    else
      {:error, error} ->
        error_msg = "Can't calculate NVT ratio for project with coinmarketcap_id: #{slug}."
        Logger.warn(error_msg <> " Reason: #{inspect(error)}")
        {:error, error_msg}
    end
  end

  def historical_balance(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, address: address},
        _resolution
      ) do
    with {:ok, result} <- HistoricalBalance.historical_balance(address, slug, from, to, interval) do
      {:ok, result}
    else
      {:error, error} ->
        Logger.warn(
          "Can't calculate historical balances for project with coinmarketcap_id #{slug}. Reason: #{
            inspect(error)
          }"
        )

        {:error, "Can't calculate historical balances for project with coinmarketcap_id #{slug}"}
    end
  end
end
