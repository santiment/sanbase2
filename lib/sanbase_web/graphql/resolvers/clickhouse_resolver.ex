defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils
  alias SanbaseWeb.Graphql.Helpers.Utils

  alias Sanbase.Clickhouse.{
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
        error_msg = generate_error_message("gas used")
        log_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def network_growth(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract, _} <- Project.contract_info_by_slug(slug),
         {:ok, network_growth} <- NetworkGrowth.network_growth(contract, from, to, interval) do
      {:ok, network_growth}
    else
      {:error, error} ->
        error_msg = generate_error_message_for_project("network growth", slug)
        log_error(error_msg, error)
        {:error, error_msg}
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
        error_msg = generate_error_message("mining pools distribution")
        log_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def mvrv_ratio(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    # TODO: Check if interval is a whole day as in token circulation
    case MVRV.mvrv_ratio(slug, from, to, interval) do
      {:ok, mvrv_ratio} ->
        {:ok, mvrv_ratio}

      {:error, error} ->
        error_msg = generate_error_message_for_project("MVRV ratio", slug)
        log_error(error_msg, error)
        {:error, error_msg}
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
        error_msg = generate_error_message_for_project("daily active deposits", slug)
        log_error(error_msg, error)
        {:error, error_msg}
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
        error_msg = generate_error_message_for_project("realized value", slug)
        log_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def nvt_ratio(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    case NVT.nvt_ratio(slug, from, to, interval) do
      {:ok, nvt_ratio} ->
        {:ok, nvt_ratio}

      {:error, error} ->
        error_msg = generate_error_message_for_project("NVT ratio", slug)
        log_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def historical_balance(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, address: address},
        _resolution
      ) do
    case HistoricalBalance.historical_balance(address, slug, from, to, interval) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        error_msg = generate_error_message_for_project("historical balances", slug)
        log_error(error_msg, error)
        {:error, error_msg}
    end
  end

  defp log_error(error_msg, error) do
    Logger.warn(error_msg <> " Reason: #{inspect(error)}")
  end

  defp generate_error_message(metric_name) do
    "Can't calculate #{metric_name}."
  end

  defp generate_error_message_for_project(metric_name, slug) do
    "Can't calculate #{metric_name} for project with coinmarketcap_id: #{slug}."
  end
end
