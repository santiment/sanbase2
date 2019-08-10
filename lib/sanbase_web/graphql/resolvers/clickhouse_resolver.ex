defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project
  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 7]

  import Absinthe.Resolution.Helpers, only: [on_load: 2]

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  import Sanbase.Utils.ErrorHandling,
    only: [log_graphql_error: 2, graphql_error_msg: 1, graphql_error_msg: 2, graphql_error_msg: 3]

  alias Sanbase.Clickhouse.HistoricalBalance.MinersBalance

  alias Sanbase.Clickhouse.{
    DailyActiveDeposits,
    GasUsed,
    HistoricalBalance,
    MiningPoolsDistribution,
    NVT,
    PercentOfTokenSupplyOnExchanges,
    TopHolders,
    ShareOfDeposits,
    Metric
  }

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 50

  @one_hour_in_seconds 3_600

  def top_holders_percent_of_total_supply(
        _root,
        %{
          slug: slug,
          number_of_holders: number_of_holders,
          from: from,
          to: to,
          interval: interval
        },
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, percent_of_total_supply} <-
           TopHolders.percent_of_total_supply(
             contract,
             token_decimals,
             number_of_holders,
             from,
             to,
             interval
           ) do
      {:ok, percent_of_total_supply}
    else
      {:error, error} ->
        error_msg = graphql_error_msg("Top Holders - percent of total supply", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def gas_used(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    case GasUsed.gas_used(slug, from, to, interval) do
      {:ok, gas_used} ->
        {:ok, gas_used}

      {:error, error} ->
        error_msg = graphql_error_msg("Gas Used", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def network_growth(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    Metric.get("network_growth", slug, from, to, interval)
    |> transform_values(:new_addresses)
  end

  def mining_pools_distribution(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    case MiningPoolsDistribution.distribution(slug, from, to, interval) do
      {:ok, distribution} ->
        {:ok, distribution}

      {:error, error} ->
        error_msg = graphql_error_msg("Mining Pools Distribution")
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def miners_balance(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(
             MinersBalance,
             slug,
             from,
             to,
             interval,
             86400,
             @datapoints
           ),
         {:ok, balance} <-
           MinersBalance.historical_balance(slug, from, to, interval) do
      {:ok, balance}
    else
      {:error, error} ->
        error_msg = graphql_error_msg("Miners Balance", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def mvrv_ratio(_root, args, resolution) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "mvrv_usd_20y")
    })
    |> transform_values(:mvrv_ratio)
  end

  def token_circulation(
        _root,
        args,
        resolution
      ) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "stack_circulation_20y")
    })
    |> transform_values(:token_circulation)
  end

  def token_velocity(
        _root,
        args,
        resolution
      ) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "token_velocity")
    })
    |> transform_values(:token_velocity)
  end

  def daily_active_addresses(
        _root,
        args,
        resolution
      ) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "daily_active_addresses")
    })
    |> transform_values(:daily_active_addresses)
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
        ) || 0

      {:ok, average_daily_active_addresses}
    else
      {:error, {:missing_contract, _}} ->
        {:ok, 0}

      {:error, error} ->
        error_msg = "Can't fetch average daily active addresses for #{Project.describe(project)}"
        log_graphql_error(error_msg, error)
        {:ok, 0}
    end
  end

  def daily_active_deposits(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract, _} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(
             DailyActiveDeposits,
             contract,
             from,
             to,
             interval,
             @one_hour_in_seconds,
             @datapoints
           ),
         {:ok, active_deposits} <-
           DailyActiveDeposits.active_deposits(contract, from, to, interval) do
      {:ok, active_deposits}
    else
      {:error, error} ->
        error_msg = graphql_error_msg("Daily Active Deposits", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def realized_value(
        _root,
        args,
        resolution
      ) do
    MetricResolver.get_timeseries_data(%{}, args, %{
      resolution
      | source: Map.put(resolution.source, :metric, "stack_realized_cap_usd")
    })
    |> transform_values(:stack_realized_cap_usd)
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
        error_msg = graphql_error_msg("NVT Ratio", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def assets_held_by_address(_root, %{address: address}, _resolution) do
    HistoricalBalance.assets_held_by_address(address)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        error_msg = graphql_error_msg("Assets held by address", address, description: "address")
        log_graphql_error(error_msg, error)
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
        error_msg = graphql_error_msg("Historical Balances", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def percent_of_token_supply_on_exchanges(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    case PercentOfTokenSupplyOnExchanges.percent_on_exchanges(slug, from, to, interval) do
      {:ok, percent_tokens_on_exchanges} ->
        {:ok, percent_tokens_on_exchanges}

      {:error, error} ->
        error_msg = graphql_error_msg("Percent of Token Supply on Exchanges", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  def share_of_deposits(
        _root,
        %{slug: slug, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, contract, _} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(
             ShareOfDeposits,
             contract,
             from,
             to,
             interval,
             @one_hour_in_seconds,
             @datapoints
           ),
         {:ok, share_of_deposits} <-
           ShareOfDeposits.share_of_deposits(contract, from, to, interval) do
      {:ok, share_of_deposits}
    else
      {:error, {:missing_contract, error_msg}} ->
        {:error, error_msg}

      {:error, error} ->
        error_msg = graphql_error_msg("Share of Deposits", slug)
        log_graphql_error(error_msg, error)
        {:error, error_msg}
    end
  end

  defp transform_values({:error, error}, _), do: {:error, error}

  defp transform_values({:ok, data}, value_name) do
    data =
      data
      |> Enum.map(fn %{datetime: datetime, value: value} ->
        %{
          value_name => value,
          datetime: datetime
        }
      end)

    {:ok, data}
  end
end
