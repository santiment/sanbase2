defmodule SanbaseWeb.Graphql.Resolvers.ProjectTransactionsResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Async

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse
  alias SanbaseWeb.Graphql.Helpers.{Cache, Utils}

  def token_top_transactions(
        %Project{id: id} = project,
        %{from: from, to: to, limit: limit} = args,
        _resolution
      ) do
    with {:ok, contract_address, token_decimals} <- Utils.project_to_contract_info(project) do
      limit = Enum.max([limit, 100])

      async(
        Cache.func(
          fn ->
            {:ok, token_transactions} =
              Clickhouse.Erc20Transfers.token_top_transfers(
                contract_address,
                from,
                to,
                limit,
                token_decimals
              )

            result =
              token_transactions
              |> Clickhouse.MarkExchanges.mark_exchange_wallets()

            {:ok, result}
          end,
          {:token_top_transfers, id},
          args
        )
      )
    else
      error ->
        Logger.info("Cannot get token top transfers. Reason: #{inspect(error)}")

        {:ok, []}
    end
  end

  def eth_spent(%Project{} = project, %{days: days}, _resolution) do
    today = Timex.now()
    days_ago = Timex.shift(today, days: -days)

    async(calculate_eth_spent_cached(project, days_ago, today))
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
    with projects when is_list(projects) <- Project.erc20_projects() do
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
    Project.erc20_projects()
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
    with {:ok, eth_addresses} <- Project.eth_addresses(project),
         {:ok, eth_spent} <-
           Clickhouse.EthTransfers.eth_spent(eth_addresses, from_datetime, to_datetime) do
      {:ok, eth_spent}
    else
      error ->
        Logger.warn(
          "Cannot calculate ETH spent for #{Project.describe(project)}. Reason: #{inspect(error)}"
        )

        {:ok, nil}
    end
  rescue
    e ->
      Logger.error(
        "Error raised while calculating ETH spent for #{Project.describe(project)}. Reason: #{
          inspect(e)
        }"
      )

      {:ok, nil}
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

  defp calculate_eth_spent_over_time(%Project{id: id} = project, from, to, interval) do
    with {:ok, eth_addresses} <- Project.eth_addresses(project),
         interval when is_integer(interval) <-
           Sanbase.DateTimeUtils.compound_duration_to_seconds(interval),
         {:ok, eth_spent_over_time} <-
           Clickhouse.EthTransfers.eth_spent_over_time(eth_addresses, from, to, interval) do
      {:ok, eth_spent_over_time}
    else
      error ->
        Logger.warn(
          "Cannot calculate ETH spent over time for project with id #{id}. Reason: #{
            inspect(error)
          }"
        )

        {:ok, []}
    end
  rescue
    e ->
      Logger.error(
        "Exception raised while calculating ETH spent over time for #{Project.describe(project)}. Reason: #{
          inspect(e)
        }"
      )

      {:ok, []}
  end

  defp calculate_eth_top_transactions(%Project{} = project, %{
         from: from,
         to: to,
         transaction_type: trx_type,
         limit: limit
       }) do
    with trx_type <- trx_type,
         {:ok, project_addresses} <- Project.eth_addresses(project),
         {:ok, eth_transactions} <-
           Clickhouse.EthTransfers.top_wallet_transfers(
             project_addresses,
             from,
             to,
             limit,
             trx_type
           ) do
      result = eth_transactions

      {:ok, result}
    else
      error ->
        Logger.warn(
          "Cannot fetch ETH transactions for project with id #{project.id}. Reason: #{
            inspect(error)
          }"
        )

        {:ok, []}
    end
  end
end
