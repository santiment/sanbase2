defmodule SanbaseWeb.Graphql.Resolvers.ProjectTransactionsResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Async
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Clickhouse.Label

  @max_concurrency 100

  def token_top_transactions(
        %Project{} = project,
        args,
        _resolution
      ) do
    async(fn -> calculate_token_top_transactions(project, args) end)
  end

  defp calculate_token_top_transactions(%Project{slug: slug} = project, args) do
    %{from: from, to: to, limit: limit} = args
    limit = Enum.min([limit, 100])

    with {:ok, contract_address, token_decimals} <- Project.contract_info(project),
         {:ok, token_transactions} <-
           Clickhouse.Erc20Transfers.token_top_transfers(
             contract_address,
             from,
             to,
             limit,
             token_decimals
           ),
         {:ok, token_transactions} <-
           Clickhouse.MarkExchanges.mark_exchange_wallets(token_transactions),
         {:ok, token_transactions} <- Label.add_labels(slug, token_transactions) do
      {:ok, token_transactions}
    else
      {:error, {:missing_contract, _}} ->
        {:ok, []}

      error ->
        Logger.warn(
          "Cannot fetch top token transactions for project with id #{project.id}. Reason: #{
            inspect(error)
          }"
        )

        {:nocache, {:ok, []}}
    end
  end

  def eth_spent(%Project{} = project, %{days: days}, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :eth_spent, %{
      project: project,
      days: days
    })
    |> on_load(&eth_spent_from_loader(&1, project, days))
  end

  def eth_spent_from_loader(loader, %Project{id: id}, days) do
    loader
    |> Dataloader.get(SanbaseDataloader, :eth_spent, days)
    |> case do
      %{} = eth_spent_map ->
        case Map.get(eth_spent_map, id) do
          nil -> {:ok, 0}
          result -> result
        end

      _ ->
        {:nocache, {:ok, nil}}
    end
  end

  def eth_spent_over_time(
        %Project{} = project,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    async(calculate_eth_spent_over_time_cached(project, from, to, interval))
  end

  @doc ~s"""
  Returns the accumulated ETH spent by all ERC20 projects for a given time period.
  """
  def eth_spent_by_all_projects(_, %{from: from, to: to}, _resolution) do
    with projects when is_list(projects) <- Project.List.projects() do
      total_eth_spent =
        projects
        |> Sanbase.Parallel.map(
          &calculate_eth_spent_cached(&1, from, to).(),
          timeout: 25_000,
          max_concurrency: @max_concurrency
        )
        |> Enum.map(fn
          {:ok, value} when not is_nil(value) -> value
          _ -> 0
        end)
        |> Enum.sum()

      {:ok, total_eth_spent}
    end
  end

  @doc ~s"""
  Returns the accumulated ETH spent by all ERC20 projects for a given time period.
  """
  def eth_spent_by_erc20_projects(_, %{from: from, to: to}, _resolution) do
    with projects when is_list(projects) <- Project.List.erc20_projects() do
      total_eth_spent =
        projects
        |> Sanbase.Parallel.map(&calculate_eth_spent_cached(&1, from, to).(),
          timeout: 25_000,
          max_concurrency: @max_concurrency
        )
        |> Enum.map(fn
          {:ok, value} when not is_nil(value) -> value
          _ -> 0
        end)
        |> Enum.sum()

      {:ok, total_eth_spent}
    end
  end

  @doc ~s"""
  Returns a list of ETH spent by all ERC20 projects for a given time period,
  grouped by the given `interval`.
  """
  def eth_spent_over_time_by_erc20_projects(
        _root,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    Project.List.erc20_projects() |> eth_spent_over_time(from, to, interval)
  end

  @doc ~s"""
  Returns a list of ETH spent by all projects for a given time period,
  grouped by the given `interval`.
  """

  def eth_spent_over_time_by_all_projects(
        _root,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    Project.List.projects() |> eth_spent_over_time(from, to, interval)
  end

  defp eth_spent_over_time(projects, from, to, interval) do
    projects
    |> Sanbase.Parallel.map(
      &calculate_eth_spent_over_time_cached(&1, from, to, interval).(),
      timeout: 25_000,
      max_concurrency: @max_concurrency
    )
    |> combine_eth_spent_by_all_projects()
  end

  def eth_top_transactions(
        %Project{} = project,
        args,
        _resolution
      ) do
    async(fn -> calculate_eth_top_transactions(project, args) end)
  end

  defp calculate_eth_top_transactions(%Project{slug: slug} = project, args) do
    %{from: from, to: to, transaction_type: trx_type, limit: limit} = args
    limit = Enum.min([limit, 100])

    with {:ok, eth_addresses} <- Project.eth_addresses(project),
         {:ok, eth_transactions} <-
           Clickhouse.EthTransfers.top_wallet_transfers(
             eth_addresses,
             from,
             to,
             limit,
             trx_type
           ),
         {:ok, eth_transactions} <-
           Clickhouse.MarkExchanges.mark_exchange_wallets(eth_transactions),
         {:ok, eth_transactions} <- Label.add_labels(slug, eth_transactions) do
      {:ok, eth_transactions}
    else
      error ->
        Logger.warn(
          "Cannot fetch top ETH transactions for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        {:nocache, {:ok, []}}
    end
  end

  # Private functions

  defp calculate_eth_spent_cached(%Project{id: id} = project, from_datetime, to_datetime) do
    Cache.wrap(
      fn -> calculate_eth_spent(project, from_datetime, to_datetime) end,
      {:eth_spent, id},
      %{from_datetime: from_datetime, to_datetime: to_datetime}
    )
  end

  defp calculate_eth_spent(%Project{} = project, from_datetime, to_datetime) do
    with {_, {:ok, eth_addresses}} when eth_addresses != [] <-
           {:eth_addresses, Project.eth_addresses(project)},
         {:ok, eth_spent} <-
           Clickhouse.HistoricalBalance.EthSpent.eth_spent(
             eth_addresses,
             from_datetime,
             to_datetime
           ) do
      {:ok, eth_spent}
    else
      {:eth_addresses, _} ->
        {:ok, nil}

      error ->
        Logger.warn(
          "Cannot calculate ETH spent for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        {:nocache, {:ok, nil}}
    end
  end

  defp calculate_eth_spent_over_time_cached(
         %Project{id: id} = project,
         from,
         to,
         interval
       ) do
    Cache.wrap(
      fn -> calculate_eth_spent_over_time(project, from, to, interval) end,
      {:eth_spent_over_time, id},
      %{from: from, to: to, interval: interval}
    )
  end

  defp calculate_eth_spent_over_time(%Project{} = project, from, to, interval) do
    with {_, {:ok, eth_addresses}} when eth_addresses != [] <-
           {:eth_addresses, Project.eth_addresses(project)},
         {:ok, eth_spent_over_time} <-
           Clickhouse.HistoricalBalance.EthSpent.eth_spent_over_time(
             eth_addresses,
             from,
             to,
             interval
           ) do
      {:ok, eth_spent_over_time}
    else
      {:eth_addresses, _} ->
        {:ok, []}

      error ->
        Logger.warn(
          "Cannot calculate ETH spent over time for for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        {:nocache, {:ok, []}}
    end
  end

  # Combines a list of lists of ethereum spent data for many projects to a list of ethereum spent data.
  # The entries at the same positions in each list are summed.
  defp combine_eth_spent_by_all_projects(eth_spent_over_time_list) do
    total_eth_spent_over_time =
      eth_spent_over_time_list
      |> Enum.reject(fn
        {:ok, elem} when elem != [] and elem != nil -> false
        _ -> true
      end)
      |> Enum.map(fn {:ok, data} -> data end)
      |> Stream.zip()
      |> Stream.map(&Tuple.to_list/1)
      |> Enum.map(&reduce_eth_spent/1)

    {:ok, total_eth_spent_over_time}
  end

  defp reduce_eth_spent([%{datetime: datetime} | _] = values) do
    total_eth_spent = values |> Enum.map(& &1.eth_spent) |> Enum.sum()
    %{datetime: datetime, eth_spent: total_eth_spent}
  end
end
