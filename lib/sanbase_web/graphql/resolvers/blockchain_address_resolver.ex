defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, changeset_errors_string: 1]

  alias Sanbase.BlockchainAddress
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Clickhouse.{Label, EthTransfers, Erc20Transfers, MarkExchanges}

  @recent_transactions_type_map %{
    eth: %{module: EthTransfers, slug: "ethereum"},
    erc20: %{module: Erc20Transfers, slug: nil}
  }

  def recent_transactions(
        _root,
        %{
          address: address,
          type: type,
          page: page,
          page_size: page_size,
          only_sender: only_sender
        },
        _resolution
      ) do
    page_size = Enum.min([page_size, 100])
    page_size = Enum.max([page_size, 1])

    module = @recent_transactions_type_map[type].module
    slug = @recent_transactions_type_map[type].slug

    with {:ok, recent_transactions} <-
           module.recent_transactions(address,
             page: page,
             page_size: page_size,
             only_sender: only_sender
           ),
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
        reason = changeset_errors_string(changeset)
        {:error, "Cannot get blockchain address #{infrastructure} #{address}. Reason: #{reason}"}

      {:error, error} ->
        {:error, error}
    end
  end

  def labels(%{address: address} = root, _args, %{context: %{loader: loader}}) do
    address = BlockchainAddress.to_internal_format(address)

    loader
    |> Dataloader.load(SanbaseDataloader, :address_labels, address)
    |> on_load(fn loader ->
      santiment_labels = Dataloader.get(loader, SanbaseDataloader, :address_labels, address) || []

      # The root can be built either from a BlockchainAddress in case the
      # `blockchain_address` query is used, or from a BlockchainAddressUserPair
      # in casethe address is part of a watchlist. In the second case, the root
      # has an additional `labels` key which holds the list of user-defined labels
      # for that address. The santiment defined labels from CH are provided with a
      # `origin: "santiment"` key-value pair so they could be distinguished from
      # the user-defined labels.
      user_labels =
        Map.get(root, :labels, [])
        |> Enum.map(fn label ->
          label |> Map.from_struct() |> Map.put(:origin, "user")
        end)

      {:ok, user_labels ++ santiment_labels}
    end)
  end

  def balance(%{address: address}, %{selector: selector}, %{context: %{loader: loader}}) do
    address = BlockchainAddress.to_internal_format(address)

    loader
    |> Dataloader.load(SanbaseDataloader, :address_selector_current_balance, {address, selector})
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(
         loader,
         SanbaseDataloader,
         :address_selector_current_balance,
         {address, selector}
       )}
    end)
  end

  def balance_dominance(%{address: address}, %{selector: selector}, %{context: %{loader: loader}}) do
    address = BlockchainAddress.to_internal_format(address)

    loader
    |> Dataloader.load(SanbaseDataloader, :address_selector_current_balance, {address, selector})
    |> on_load(fn loader ->
      [address_balance, total_balance] =
        Dataloader.get_many(
          loader,
          SanbaseDataloader,
          :address_selector_current_balance,
          [{address, selector}, {:total_balance, selector}]
        )

      dominance =
        Sanbase.Math.percent_of(address_balance, total_balance, type: :between_0_and_100)
        |> Sanbase.Math.round_float()

      {:ok, dominance}
    end)
  end

  def balance_change(%{address: address}, %{selector: selector, from: from, to: to}, %{
        context: %{loader: loader}
      }) do
    address = BlockchainAddress.to_internal_format(address)

    loader
    |> Dataloader.load(
      SanbaseDataloader,
      :address_selector_balance_change,
      {address, selector, from, to}
    )
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(
         loader,
         SanbaseDataloader,
         :address_selector_balance_change,
         {address, selector, from, to}
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
