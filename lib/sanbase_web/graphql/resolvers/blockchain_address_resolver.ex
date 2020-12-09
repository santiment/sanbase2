defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]

  alias Sanbase.BlockchainAddress
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Utils.ErrorHandling
  alias Sanbase.Clickhouse.{Label, EthTransfers, Erc20Transfers, MarkExchanges}

  @recent_transactions_type_map %{
    eth: %{module: EthTransfers, slug: "ethereum"},
    erc20: %{module: Erc20Transfers, slug: nil}
  }

  def recent_transactions(
        _root,
        %{address: address, type: type, page: page, page_size: page_size},
        _resolution
      ) do
    page_size = Enum.min([page_size, 100])
    page_size = Enum.max([page_size, 1])

    module = @recent_transactions_type_map[type].module
    slug = @recent_transactions_type_map[type].slug

    with {:ok, recent_transactions} <-
           module.recent_transactions(address, page, page_size),
         {:ok, recent_transactions} <-
           MarkExchanges.mark_exchange_wallets(recent_transactions),
         {:ok, recent_transactions} <-
           Label.add_labels(slug, recent_transactions) do
      {:ok, recent_transactions}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Recent transactions", %{address: address}, error)}
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

  def balance(%{address: address}, %{selector: selector}, %{context: %{loader: loader}}) do
    address = BlockchainAddress.to_internal_format(address)

    loader
    |> Dataloader.load(SanbaseDataloader, :current_address_selector_balance, {address, selector})
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(
         loader,
         SanbaseDataloader,
         :current_address_selector_balance,
         {address, selector}
       )}
    end)
  end

  def blockchain_address_id(%{id: id}, _args, %{
        context: %{loader: loader}
      }) do
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
