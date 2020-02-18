defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project
  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 7]

  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Sanbase.DateTimeUtils, only: [round_datetime: 2]

  alias SanbaseWeb.Graphql.SanbaseDataloader

  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]

  alias Sanbase.Clickhouse.{
    RealizedValue,
    GasUsed,
    MiningPoolsDistribution,
    NetworkGrowth,
    PercentOfTokenSupplyOnExchanges,
    TopHolders,
    ShareOfDeposits
  }

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 300

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

  def mvrv_ratio(_root, %{slug: _, from: _, to: _, interval: _} = args, _resolution) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "mvrv_usd"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :ratio)
  end

  def token_circulation(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "circulation_1d"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :token_circulation)
  end

  def token_velocity(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "velocity"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :token_velocity)
  end

  def daily_active_addresses(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "daily_active_addresses"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :active_addresses)
  end

  @doc ~S"""
  Returns the average number of daily active addresses for the last 30 days
  """
  def average_daily_active_addresses(
        %Project{} = project,
        args,
        %{context: %{loader: loader}}
      ) do
    to = Map.get(args, :to, Timex.now()) |> round_datetime(300)
    from = Map.get(args, :from, Timex.shift(to, days: -30)) |> round_datetime(300)

    data = %{project: project, from: from, to: to}

    loader
    |> Dataloader.load(SanbaseDataloader, :average_daily_active_addresses, data)
    |> on_load(&average_daily_active_addresses_on_load(&1, data))
  end

  defp average_daily_active_addresses_on_load(loader, data) do
    %{project: project, from: from, to: to} = data

    # The dataloader result is a map where the values are maps, too.
    # The top level keys are `{from, to}` so if a query like:
    # {
    #  allProjects{
    #    avg1: averageDailyActiveAddresses(from: <from1>, to: <to1>)
    #    avg2: averageDailyActiveAddresses(from: <from2>, to: <to2>)
    #  }
    # }
    # will correctly group and calculate the different average addresses.
    average_daa_activity_map =
      loader
      |> Dataloader.get(SanbaseDataloader, :average_daily_active_addresses, {from, to}) ||
        %{}

    case Map.get(average_daa_activity_map, project.slug) do
      value when is_number(value) ->
        {:ok, value}

      _ ->
        case Project.contract_info(project) do
          # If we do not have an ok tuple but there is a contract then we failed to
          # fetch that value, so it won't be cached
          {:ok, _, _} -> {:nocache, {:ok, 0}}
          _ -> {:ok, nil}
        end
    end
  end

  def daily_active_deposits(
        _root,
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "active_deposits"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :active_deposits)
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
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    with {:ok, nvt_circulation} <-
           SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
             %{},
             args,
             %{source: %{metric: "nvt"}}
           ),
         {:ok, nvt_transaction_volume} <-
           SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
             %{},
             args,
             %{source: %{metric: "nvt_transaction_volume"}}
           ) do
      result =
        Enum.zip([nvt_circulation, nvt_transaction_volume])
        |> Enum.map(fn {%{datetime: datetime, value: nvt_ratio_circulation},
                        %{value: nvt_transaction_volume}} ->
          %{
            datetime: datetime,
            nvt_ratio_circulation: nvt_ratio_circulation,
            nvt_ratio_tx_volume: nvt_transaction_volume
          }
        end)

      {:ok, result}
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
