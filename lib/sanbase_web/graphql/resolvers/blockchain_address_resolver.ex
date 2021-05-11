defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  import Sanbase.Utils.ErrorHandling,
    only: [
      handle_graphql_error: 3,
      handle_graphql_error: 4,
      maybe_handle_graphql_error: 2
    ]

  alias Sanbase.BlockchainAddress
  alias Sanbase.BlockchainAddress.BlockchainAddressUserPair

  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Clickhouse.{Label, MarkExchanges}
  alias Sanbase.Transfers

  @recent_transactions_type_map %{
    eth: %{module: Transfers.EthTransfers, slug: "ethereum"},
    erc20: %{module: Transfers.Erc20Transfers, slug: nil}
  }

  def list_all_labels(_root, args, _resolution) do
    Map.get(args, :blockchain, :all)
    |> Label.list_all()
  end

  def top_transactions(
        _root,
        %{address_selector: address_selector, slug: slug, from: from, to: to} = args,
        _resolution
      ) do
    %{page: page, page_size: page_size} = args_to_page_args(args)
    address = Map.fetch!(address_selector, :address)
    type = Map.get(address_selector, :transacion_type, :all)

    with {:ok, transactions} <-
           Transfers.top_wallet_transactions(slug, address, from, to, page, page_size, type),
         {:ok, transactions} <- MarkExchanges.mark_exchange_wallets(transactions),
         {:ok, transactions} <- Label.add_labels(slug, transactions) do
      {:ok, transactions}
    end
  end

  def top_transactions(
        _root,
        %{slug: slug, from: from, to: to} = args,
        _resolution
      ) do
    %{page: page, page_size: page_size} = args_to_page_args(args)

    with {:ok, transactions} <-
           Sanbase.Transfers.top_transactions(slug, from, to, page, page_size),
         {:ok, transactions} <- MarkExchanges.mark_exchange_wallets(transactions),
         {:ok, transactions} <- Label.add_labels(slug, transactions) do
      {:ok, transactions}
    end
  end

  def recent_transactions(
        _root,
        %{address: address, type: type, only_sender: only_sender} = args,
        _resolution
      ) do
    %{page: page, page_size: page_size} = args_to_page_args(args)

    module = @recent_transactions_type_map[type].module
    slug = @recent_transactions_type_map[type].slug
    opts = [page: page, page_size: page_size, only_sender: only_sender]

    with {:ok, transactions} <- module.recent_transactions(address, opts),
         {:ok, transactions} <-
           MarkExchanges.mark_exchange_wallets(transactions),
         {:ok, transactions} <- Label.add_labels(slug, transactions) do
      {:ok, transactions}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Recent transactions", %{address: address}, error)}
    end
  end

  defp args_to_page_args(args) do
    page = Map.get(args, :page, 1)
    page_size = Map.get(args, :page_size, 10)
    page_size = Enum.min([page_size, 100])
    page_size = Enum.max([page_size, 1])

    %{page: page, page_size: page_size}
  end

  def blockchain_address(_root, %{selector: selector}, _resolution) do
    BlockchainAddress.by_selector(selector)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Blockchain Address",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def blockchain_address_user_pair(_root, %{selector: selector}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case BlockchainAddressUserPair.by_selector(selector, current_user.id) do
      {:ok, pair} ->
        {:ok, pair}

      {:error, _error} ->
        case selector do
          %{address: address, infrastructure: infrastructure} ->
            BlockchainAddressUserPair.create(
              address,
              infrastructure,
              current_user.id
            )

          %{id: id} ->
            {:error,
             """
             Blockchain address user pair with id #{id} does not exist. In order \
             to create a new pair for the current user, provide `address` and `infrastrucutre`
             in the selector.
             """}
        end
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Blockchain Address User Pair",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def update_blockchain_address_user_pair(
        _root,
        %{selector: selector} = args,
        %{
          context: %{auth: %{current_user: current_user}}
        }
      ) do
    with {:ok, pair} <-
           BlockchainAddressUserPair.by_selector(selector, current_user.id),
         {:ok, pair} <- BlockchainAddressUserPair.update(pair, args) do
      {:ok, pair}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Update Blockchain Address User Pair",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def labels(root, _args, %{context: %{loader: loader}}) do
    case root_to_raw_address(root) do
      nil ->
        {:ok, []}

      address ->
        address
        |> BlockchainAddress.to_internal_format()

        loader
        |> Dataloader.load(SanbaseDataloader, :address_labels, address)
        |> on_load(fn loader ->
          santiment_labels =
            Dataloader.get(loader, SanbaseDataloader, :address_labels, address) ||
              []

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
  end

  def infrastructure(root, _args, %{context: %{loader: loader}}) do
    case root_to_blockchain_address(root) do
      %{infrastructure: infrastructure} when is_binary(infrastructure) ->
        {:ok, infrastructure}

      %{infrastructure_id: infrastructure_id} ->
        loader
        |> Dataloader.load(
          SanbaseDataloader,
          :infrastructure,
          infrastructure_id
        )
        |> on_load(fn loader ->
          {:ok,
           Dataloader.get(
             loader,
             SanbaseDataloader,
             :infrastructure,
             infrastructure_id
           )}
        end)
    end
  end

  def balance(root, %{selector: selector}, %{context: %{loader: loader}}) do
    address = root |> root_to_raw_address() |> BlockchainAddress.to_internal_format()

    loader
    |> Dataloader.load(
      SanbaseDataloader,
      :address_selector_current_balance,
      {address, selector}
    )
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

  def balance_dominance(root, %{selector: selector}, %{
        context: %{loader: loader}
      }) do
    address = root |> root_to_raw_address() |> BlockchainAddress.to_internal_format()

    loader
    |> Dataloader.load(
      SanbaseDataloader,
      :address_selector_current_balance,
      {address, selector}
    )
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

  def balance_change(root, %{selector: selector, from: from, to: to}, %{
        context: %{loader: loader}
      }) do
    address = root |> root_to_raw_address() |> BlockchainAddress.to_internal_format()

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

  def blockchain_address_id(%Sanbase.Comment{id: id}, _args, %{
        context: %{loader: loader}
      }) do
    loader
    |> Dataloader.load(SanbaseDataloader, :comment_blockchain_address_id, id)
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(
         loader,
         SanbaseDataloader,
         :comment_blockchain_address_id,
         id
       )}
    end)
  end

  def comments_count(root, _args, %{context: %{loader: loader}}) do
    root_address = root_to_blockchain_address(root)
    id = root_address.id

    loader
    |> Dataloader.load(
      SanbaseDataloader,
      :blockchain_addresses_comments_count,
      id
    )
    |> on_load(fn loader ->
      {:ok,
       Dataloader.get(
         loader,
         SanbaseDataloader,
         :blockchain_addresses_comments_count,
         id
       ) || 0}
    end)
  end

  # Private functions

  defp root_to_blockchain_address(%{blockchain_address: blockchain_address}),
    do: blockchain_address

  defp root_to_blockchain_address(%{address: _} = blockchain_address),
    do: blockchain_address

  defp root_to_raw_address(%{blockchain_address: %{address: address}}),
    do: address

  defp root_to_raw_address(%{address: address}), do: address
end
