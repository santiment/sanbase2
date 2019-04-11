defmodule SanbaseWeb.Graphql.Resolvers.ProjectTransactionsResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Async
  import Absinthe.Resolution.Helpers, except: [async: 1]
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse
  alias SanbaseWeb.Graphql.Cache
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def token_top_transactions(
        %Project{id: id} = project,
        args,
        _resolution
      ) do
    async(
      Cache.func(
        fn -> calculate_token_top_transactions(project, args) end,
        {:token_top_transactions, id},
        args
      )
    )
  end

  defp calculate_token_top_transactions(%Project{} = project, %{
         from: from,
         to: to,
         limit: limit
       }) do
    limit = Enum.min([limit, 100])

    with {:contract, {:ok, contract_address, token_decimals}} <-
           {:contract, Project.contract_info(project)},
         {:ok, token_transactions} <-
           Clickhouse.Erc20Transfers.token_top_transfers(
             contract_address,
             from,
             to,
             limit,
             token_decimals
           ),
         {:ok, token_transactions} <-
           Clickhouse.MarkExchanges.mark_exchange_wallets(token_transactions) do
      {:ok, token_transactions}
    else
      {:contract, _} ->
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
      from: Timex.shift(Timex.now(), days: -days),
      to: Timex.now()
    })
    |> on_load(&eth_spent_from_loader(&1, project))
  end

  def eth_spent_from_loader(loader, %Project{id: id}) do
    loader
    |> Dataloader.get(SanbaseDataloader, :eth_spent, id)
    |> case do
      nil -> {:ok, 0}
      result -> result
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
  def eth_spent_by_erc20_projects(_, %{from: from, to: to}, _resolution) do
    with projects when is_list(projects) <- Project.List.erc20_projects() do
      total_eth_spent =
        projects
        |> Sanbase.Parallel.pmap(&calculate_eth_spent_cached(&1, from, to).(), timeout: 25_000)
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
    Project.List.erc20_projects()
    |> Sanbase.Parallel.pmap(&calculate_eth_spent_over_time_cached(&1, from, to, interval).(),
      timeout: 25_000
    )
    |> Clickhouse.EthTransfers.combine_eth_spent_by_all_projects()
  end

  def eth_top_transactions(
        %Project{id: id} = project,
        args,
        _resolution
      ) do
    async(
      Cache.func(
        fn -> calculate_eth_top_transactions(project, args) end,
        {:eth_top_transactions, id},
        args
      )
    )
  end

  # Private functions

  defp calculate_eth_spent_cached(%Project{id: id} = project, from_datetime, to_datetime) do
    Cache.func(
      fn -> calculate_eth_spent(project, from_datetime, to_datetime) end,
      {:eth_spent, id},
      %{from_datetime: from_datetime, to_datetime: to_datetime}
    )
  end

  defp calculate_eth_spent(%Project{} = project, from_datetime, to_datetime) do
    with {:eth_addresses, {:ok, eth_addresses}} when eth_addresses != [] <-
           {:eth_addresses, Project.eth_addresses(project)},
         {:ok, eth_spent} <-
           Clickhouse.EthTransfers.eth_spent(eth_addresses, from_datetime, to_datetime) do
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
    Cache.func(
      fn -> calculate_eth_spent_over_time(project, from, to, interval) end,
      {:eth_spent_over_time, id},
      %{from: from, to: to, interval: interval}
    )
  end

  defp calculate_eth_spent_over_time(%Project{} = project, from, to, interval) do
    with {:eth_addresses, {:ok, eth_addresses}} when eth_addresses != [] <-
           {:eth_addresses, Project.eth_addresses(project)},
         {:ok, eth_spent_over_time} <-
           Clickhouse.EthTransfers.eth_spent_over_time(eth_addresses, from, to, interval) do
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

  defp calculate_eth_top_transactions(%Project{} = project, %{
         from: from,
         to: to,
         transaction_type: trx_type,
         limit: limit
       }) do
    limit = Enum.min([limit, 100])

    with {:eth_addresses, {:ok, eth_addresses}} when eth_addresses != [] <-
           {:eth_addresses, Project.eth_addresses(project)},
         {:ok, eth_transactions} <-
           Clickhouse.EthTransfers.top_wallet_transfers(
             eth_addresses,
             from,
             to,
             limit,
             trx_type
           ),
         {:ok, eth_transactions} <-
           Clickhouse.MarkExchanges.mark_exchange_wallets(eth_transactions) do
      {:ok, eth_transactions}
    else
      {:eth_addresses, _} ->
        {:ok, []}

      error ->
        Logger.warn(
          "Cannot fetch top ETH transactions for #{Project.describe(project)}. Reason: #{
            inspect(error)
          }"
        )

        {:nocache, {:ok, []}}
    end
  end
end
