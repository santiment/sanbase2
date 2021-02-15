defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  require Logger

  alias Sanbase.Model.Project

  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Sanbase.DateTimeUtils, only: [round_datetime: 1]
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]

  alias SanbaseWeb.Graphql.SanbaseDataloader

  alias Sanbase.Clickhouse.{
    GasUsed,
    MiningPoolsDistribution,
    TopHolders
  }

  def top_holders(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          number_of_holders: number_of_holders
        },
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, top_holders} <-
           TopHolders.top_holders(
             slug,
             contract,
             token_decimals,
             from,
             to,
             number_of_holders
           ) do
      {:ok, top_holders}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Top Holders", slug, error)}
    end
  end

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

  def network_growth(_root, %{slug: _, from: _, to: _, interval: _} = args, _resolution) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      Map.put(args, :include_incomplete_data, true),
      %{source: %{metric: "network_growth"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :new_addresses)
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
    to = Map.get(args, :to, Timex.now()) |> round_datetime()
    from = Map.get(args, :from, Timex.shift(to, days: -30)) |> round_datetime()

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
    # will correctly group and calculate the different average addresses

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
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      Map.put(args, :include_incomplete_data, true),
      %{source: %{metric: "realized_value_usd"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :realized_value)
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
        %{slug: _, from: _, to: _, interval: _} = args,
        _resolution
      ) do
    SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
      %{},
      args,
      %{source: %{metric: "percent_of_total_supply_on_exchanges"}}
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :percent_on_exchanges)
  end

  def eth_fees_distribution(_root, %{from: from, to: to, limit: limit}, _res) do
    case Sanbase.Clickhouse.Fees.eth_fees_distribution(from, to, limit) do
      {:ok, fees} ->
        {:ok, fees}

      {:error, error} ->
        {:error, handle_graphql_error("ETH Fees Distribution", "ethereum", error)}
    end
  end
end
