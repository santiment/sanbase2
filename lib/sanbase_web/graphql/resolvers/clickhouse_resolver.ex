defmodule SanbaseWeb.Graphql.Resolvers.ClickhouseResolver do
  import Absinthe.Resolution.Helpers, only: [on_load: 2]
  import Sanbase.DateTimeUtils, only: [round_datetime: 1]
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]

  alias Sanbase.Project
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  alias Sanbase.Clickhouse.{
    GasUsed,
    TopHolders
  }

  require Logger

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  @doc ~S"""
  Return the amount of tokens that were transacted in or out of an exchange wallet for a given slug
  and time period
  """
  def exchange_funds_flow(root, %{slug: _, from: _, to: _, interval: _} = args, resolution) do
    MetricResolver.timeseries_data(
      root,
      args,
      Map.put(resolution, :source, %{metric: "exchange_balance"})
    )
    |> Sanbase.Utils.Transform.rename_map_keys(old_key: :value, new_key: :in_out_difference)
  end

  def realtime_top_holders(_root, %{slug: slug, page: page, page_size: page_size}, _resolution) do
    opts = [page: page, page_size: page_size]

    case TopHolders.realtime_top_holders(slug, opts) do
      {:ok, top_holders} -> {:ok, top_holders}
      {:error, error} -> {:error, handle_graphql_error("Realtime Top Holders", slug, error)}
    end
  end

  def top_holders(
        _root,
        %{slug: slug, from: from, to: to, page: page, page_size: page_size} = args,
        _resolution
      ) do
    page_size = Enum.min([args[:number_of_holders] || page_size, 100])
    labels = Map.get(args, :labels, :all)
    owners = Map.get(args, :owners, :all)
    opts = [page: page, page_size: page_size, labels: labels, owners: owners]

    case TopHolders.top_holders(slug, from, to, opts) do
      {:ok, top_holders} -> {:ok, top_holders}
      {:error, error} -> {:error, handle_graphql_error("Top Holders", slug, error)}
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
    case TopHolders.percent_of_total_supply(slug, number_of_holders, from, to, interval) do
      {:ok, percent_of_total_supply} ->
        {:ok, percent_of_total_supply}

      {:error, error} ->
        {:error, handle_graphql_error("Top Holders - percent of total supply", slug, error)}
    end
  end

  def gas_used(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    case GasUsed.gas_used(slug, from, to, interval) do
      {:ok, gas_used} ->
        {:ok, gas_used}

      {:error, error} ->
        {:error, handle_graphql_error("Gas Used", slug, error)}
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

  def percent_of_token_supply_on_exchanges(
        root,
        %{slug: _, from: _, to: _, interval: _} = args,
        resolution
      ) do
    MetricResolver.timeseries_data(
      root,
      args,
      Map.put(resolution, :source, %{metric: "percent_of_total_supply_on_exchanges"})
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
