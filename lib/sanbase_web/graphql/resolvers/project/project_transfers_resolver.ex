defmodule SanbaseWeb.Graphql.Resolvers.ProjectTransfersResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Async
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.Transfers
  alias Sanbase.Project
  alias Sanbase.Utils.BlockchainAddressUtils
  alias SanbaseWeb.Graphql.{Cache, SanbaseDataloader}
  alias Sanbase.Clickhouse.{Label, HistoricalBalance.EthSpent}

  @max_concurrency 100

  def token_top_transfers(
        %Project{} = project,
        args,
        _resolution
      ) do
    async(fn -> calculate_token_top_transfers(project, args) end)
  end

  defp calculate_token_top_transfers(%Project{slug: slug}, args) do
    %{from: from, to: to, limit: limit} = args
    limit = Enum.min([limit, 100])
    opts = [excluded_addresses: Map.get(args, :excluded_addresses, [])]

    with {:ok, transfers} <- Transfers.top_transfers(slug, from, to, 1, limit, opts),
         {:ok, transfers} <- BlockchainAddressUtils.transform_address_to_map(transfers),
         {:ok, transfers} <- Label.add_labels(slug, transfers),
         {:ok, transfers} <- Sanbase.MarkExchanges.mark_exchanges(transfers) do
      {:ok, transfers}
    else
      {:error, {:missing_contract, _}} ->
        {:ok, []}

      error ->
        Logger.warning("Cannot fetch top token transfers for project with slug #{slug}. \
          Reason: #{inspect(error)}")

        {:nocache, {:ok, []}}
    end
  end

  def eth_spent(%Project{} = project, %{days: days}, %{
        context: %{loader: loader}
      }) do
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
    Project.List.projects()
    |> calculate_eth_spent_by_projects(from, to)
  end

  @doc ~s"""
  Returns the accumulated ETH spent by all ERC20 projects for a given time period.
  """
  def eth_spent_by_erc20_projects(_, %{from: from, to: to}, _resolution) do
    Project.List.erc20_projects()
    |> calculate_eth_spent_by_projects(from, to)
  end

  defp calculate_eth_spent_by_projects(projects, from, to) do
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

  def eth_top_transfers(
        %Project{} = project,
        args,
        _resolution
      ) do
    async(fn -> calculate_eth_top_transfers(project, args) end)
  end

  defp calculate_eth_top_transfers(
         %Project{slug: "ethereum"} = project,
         args
       ) do
    %{from: from, to: to, transaction_type: _trx_type, limit: limit} = args
    limit = Enum.min([limit, 100])

    with {:ok, transfers} <- Transfers.top_transfers("ethereum", from, to, 1, limit),
         {:ok, transfers} <- BlockchainAddressUtils.transform_address_to_map(transfers),
         {:ok, transfers} <- Label.add_labels("ethereum", transfers),
         {:ok, transfers} <- Sanbase.MarkExchanges.mark_exchanges(transfers) do
      {:ok, transfers}
    else
      error ->
        Logger.warning(
          "Cannot fetch top ETH transfers for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        {:nocache, {:ok, []}}
    end
  end

  defp calculate_eth_top_transfers(%Project{slug: _slug} = project, args) do
    %{from: from, to: to, transaction_type: type, limit: limit} = args
    limit = Enum.min([limit, 100])
    infr = "ETH"

    with {:ok, addresses} <- Project.eth_addresses(project),
         {:ok, transfers} <-
           Transfers.top_wallet_transfers("ethereum", addresses, from, to, 1, limit, type),
         {:ok, transfers} <- BlockchainAddressUtils.transform_address_to_map(transfers, infr),
         {:ok, transfers} <- Label.add_labels("ethereum", transfers),
         {:ok, transfers} <- Sanbase.MarkExchanges.mark_exchanges(transfers) do
      {:ok, transfers}
    else
      error ->
        Logger.warning(
          "Cannot fetch top ETH transfers for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        {:nocache, {:ok, []}}
    end
  end

  # Private functions

  defp calculate_eth_spent_cached(
         %Project{id: id} = project,
         from_datetime,
         to_datetime
       ) do
    Cache.wrap(
      fn -> calculate_eth_spent(project, from_datetime, to_datetime) end,
      {:eth_spent, id},
      %{from_datetime: from_datetime, to_datetime: to_datetime}
    )
  end

  defp calculate_eth_spent(%Project{} = project, from_datetime, to_datetime) do
    with {_, {:ok, eth_addresses}} when eth_addresses != [] <-
           {:eth_addresses, Project.eth_addresses(project)},
         {:ok, eth_spent} <- EthSpent.eth_spent(eth_addresses, from_datetime, to_datetime) do
      {:ok, eth_spent}
    else
      {:eth_addresses, _} ->
        {:ok, nil}

      {:error, error} ->
        Logger.warning(
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
           EthSpent.eth_spent_over_time(eth_addresses, from, to, interval) do
      {:ok, eth_spent_over_time}
    else
      {:eth_addresses, _} ->
        {:ok, []}

      error ->
        Logger.warning(
          "Cannot calculate ETH spent over time for for #{Project.describe(project)}. Reason: #{inspect(error)}"
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
