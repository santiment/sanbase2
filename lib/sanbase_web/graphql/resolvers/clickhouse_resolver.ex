defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project
  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 7]

  import Absinthe.Resolution.Helpers, only: [on_load: 2]

  alias SanbaseWeb.Graphql.SanbaseDataloader

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias Sanbase.Clickhouse.HistoricalBalance.MinersBalance

  alias Sanbase.Clickhouse.{
    NVT,
    RealizedValue,
    DailyActiveDeposits,
    GasUsed,
    HistoricalBalance,
    MiningPoolsDistribution,
    NetworkGrowth,
    PercentOfTokenSupplyOnExchanges,
    TopHolders,
    ShareOfDeposits
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
        {:error, handle_graphql_error("Top Holders - percent of total supply", slug, error)}
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
        {:error, handle_graphql_error("Gas Used", slug, error)}
    end
  end

  def network_growth(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with {:ok, contract, _} <- Project.contract_info_by_slug(slug),
         {:ok, network_growth} <-
           NetworkGrowth.network_growth(contract, from, to, interval) do
      {:ok, network_growth}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Network Growth", slug, error)}
    end
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
        {:error, handle_graphql_error("Mining Pools Distribution", slug, error)}
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
             86_400,
             @datapoints
           ),
         {:ok, balance} <-
           MinersBalance.historical_balance(slug, from, to, interval) do
      {:ok, balance}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Miners Balance", slug, error)}
    end
  end

  def mvrv_ratio(_root, %{slug: _, from: _, to: _, interval: _} = args, _resolution) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "mvrv_usd"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :ratio)
  end

  def token_circulation(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "circulation_1d"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :token_circulation)
  end

  def token_velocity(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "velocity"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :token_velocity)
  end

  def daily_active_addresses(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.get_timeseries_data(
      %{},
      args,
      %{source: %{metric: "daily_active_addresses"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(:value, :active_addresses)
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
    average_daily_active_addresses =
      loader
      |> Dataloader.get(
        SanbaseDataloader,
        :average_daily_active_addresses,
        project.slug
      ) || 0

    {:ok, average_daily_active_addresses}
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
        {:error, handle_graphql_error("Daily Active Deposits", slug, error)}
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
        {:error, handle_graphql_error("Realized Value", slug, error)}
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
        {:error, handle_graphql_error("NVT Ratio", slug, error)}
    end
  end

  def assets_held_by_address(_root, %{address: address}, _resolution) do
    HistoricalBalance.assets_held_by_address(address)
    |> case do
      {:ok, result} ->
        # We do this, because many contracts emit a transfer
        # event when minting new tokens by setting 0x00...000
        # as the from address, hence 0x00...000 is "sending"
        # tokens it does not have which leads to "negative" balance

        result =
          result
          |> Enum.reject(fn %{balance: balance} -> balance < 0 end)

        {:ok, result}

      {:error, error} ->
        {:error,
         handle_graphql_error("Assets held by address", address, error, description: "address")}
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
        {:error, handle_graphql_error("Historical Balances", slug, error)}
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
        {:error, handle_graphql_error("Percent of Token Supply on Exchanges", slug, error)}
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
        {:error, handle_graphql_error("Share of Deposits", slug, error)}
    end
  end
end
