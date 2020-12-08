defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.BlockchainAddress
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Utils.ErrorHandling
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

  def blockchain_address(_root, %{selector: %{id: id}}, _resolution) do
    BlockchainAddress.by_id(id)
  end

  def blockchain_address(
        _root,
        %{selector: %{address: address, infrastructure: infrastructure}},
        _resolution
      ) do
    with {:ok, %{id: infrastructure_id}} <- Sanbase.Model.Infrastructure.by_code(infrastructure),
         {:ok, addr} <-
           BlockchainAddress.maybe_create(%{
             address: address,
             infrastructure_id: infrastructure_id
           }) do
      {:ok, addr}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        reason = ErrorHandling.changeset_errors_to_str(changeset)
        {:error, "Cannot get blockchain address #{infrastructure} #{address}. Reason: #{reason}"}

      {:error, error} ->
        {:error, error}
    end
  end

  def blockchain_address_id(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_blockchain_address_id, id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :comment_blockchain_address_id, id)}
    end)
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :blockchain_addresses_comments_count, id)
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(loader, SanbaseDataloader, :blockchain_addresses_comments_count, id) || 0}
    end)
  end
end
