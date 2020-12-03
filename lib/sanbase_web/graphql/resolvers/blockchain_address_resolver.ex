defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  alias Sanbase.Clickhouse.{Label, EthTransfers, Erc20Transfers, MarkExchanges}

  def eth_recent_transactions(
        _,
        %{address: address, page: page, page_size: page_size},
        _
      ) do
    page_size = Enum.min([page_size, 100])

    with {:ok, recent_transactions} <-
           EthTransfers.recent_transactions(address, page, page_size),
         {:ok, recent_transactions} <-
           MarkExchanges.mark_exchange_wallets(recent_transactions),
         {:ok, recent_transactions} <-
           Label.add_labels("ethereum", recent_transactions) do
      {:ok, recent_transactions}
    else
      error ->
        Logger.warn("Cannot fetch recent transactions for #{address}. Reason: #{inspect(error)}")

        {:ok, []}
    end
  end

  def token_recent_transactions(
        _,
        %{address: address, page: page, page_size: page_size},
        _
      ) do
    page_size = Enum.min([page_size, 100])

    with {:ok, recent_transactions} <-
           Erc20Transfers.recent_transactions(address, page, page_size),
         {:ok, recent_transactions} <-
           MarkExchanges.mark_exchange_wallets(recent_transactions),
         {:ok, recent_transactions} <-
           Label.add_labels(recent_transactions) do
      {:ok, recent_transactions}
    else
      error ->
        Logger.warn("Cannot fetch recent transactions for #{address}. Reason: #{inspect(error)}")

        {:ok, []}
    end
  end
end
