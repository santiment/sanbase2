defmodule SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver do
  require Logger

  import Absinthe.Resolution.Helpers, except: [async: 1]

  import Sanbase.Model.Project, only: [infrastructure_to_blockchain: 1]

  import Sanbase.Utils.ErrorHandling,
    only: [
      handle_graphql_error: 3,
      handle_graphql_error: 4,
      maybe_handle_graphql_error: 2
    ]

  alias Sanbase.BlockchainAddress
  alias Sanbase.BlockchainAddress.{BlockchainAddressUserPair, BlockchainAddressLabelChange}

  alias Sanbase.Utils.BlockchainAddressUtils
  alias SanbaseWeb.Graphql.SanbaseDataloader
  alias Sanbase.Clickhouse.Label
  alias Sanbase.Model.Project
  alias Sanbase.Transfers

  @recent_transactions_type_map %{
    eth: %{module: Transfers.EthTransfers, slug: "ethereum"},
    erc20: %{module: Transfers.Erc20Transfers, slug: nil}
  }

  def blockchain_address_labels(_root, args, _resolution) do
    Map.get(args, :blockchain, :all)
    |> Label.list_all()
  end

  def get_blockchain_address_labels(_root, _args, _resolution) do
    BlockchainAddressLabelChange.labels_list()
  end

  def top_transfers(
        _root,
        %{address_selector: address_selector, slug: slug, from: from, to: to} = args,
        _resolution
      ) do
    %{page: page, page_size: page_size} = args_to_page_args(args)
    address = Map.fetch!(address_selector, :address)
    type = Map.get(address_selector, :transacion_type, :all)

    with {:ok, transfers} <-
           Transfers.top_wallet_transfers(slug, address, from, to, page, page_size, type),
         {:ok, transfers} <- apply_in_page_order_by(transfers, args),
         {:ok, _, _, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         {:ok, transfers} <- BlockchainAddressUtils.transform_address_to_map(transfers, infr),
         {:ok, transfers} <- Label.add_labels(slug, transfers),
         {:ok, transfers} <- Sanbase.MarkExchanges.mark_exchanges(transfers) do
      {:ok, transfers}
    end
  end

  def top_transfers(
        _root,
        %{slug: slug, from: from, to: to} = args,
        _resolution
      ) do
    %{page: page, page_size: page_size} = args_to_page_args(args)

    with {:ok, transfers} <- Transfers.top_transfers(slug, from, to, page, page_size),
         {:ok, transfers} <- apply_in_page_order_by(transfers, args),
         {:ok, _, _, infr} <- Project.contract_info_infrastructure_by_slug(slug),
         {:ok, transfers} <- BlockchainAddressUtils.transform_address_to_map(transfers, infr),
         {:ok, transfers} <- Label.add_labels(slug, transfers),
         {:ok, transfers} <- Sanbase.MarkExchanges.mark_exchanges(transfers) do
      {:ok, transfers}
    end
  end

  def current_user_address_details(
        %{address: address, infrastructure: infrastructure},
        _args,
        %{context: %{loader: loader, auth: %{current_user: user}}}
      ) do
    elem = %{user_id: user.id, address: address, infrastructure: infrastructure}

    loader
    |> Dataloader.load(SanbaseDataloader, :current_user_address_details, elem)
    |> on_load(fn loader ->
      result = Dataloader.get(loader, SanbaseDataloader, :current_user_address_details, elem)

      {:ok, result}
    end)
  end

  def current_user_address_details(_root, _args, _resolution) do
    {:ok, nil}
  end

  def blockchain_address_label_changes(
        _root,
        %{selector: selector, from: from, to: to},
        _resolution
      ) do
    with %{address: address, infrastructure: infr} <-
           selector_to_address_map_do_not_create(selector),
         {:ok, changes} <- BlockchainAddressLabelChange.label_changes(address, infr, from, to),
         {:ok, changes} <- BlockchainAddressUtils.transform_address_to_map(changes, infr),
         {:ok, changes} <- Label.add_labels(infrastructure_to_blockchain(infr), changes),
         {:ok, changes} <- Sanbase.MarkExchanges.mark_exchanges(changes) do
      {:ok, changes}
    end
  end

  def blockchain_address_transaction_volume_over_time(
        _root,
        %{selector: selector, from: from, to: to, interval: interval, addresses: addresses},
        _resolution
      ) do
    %{slug: slug} = selector

    Transfers.blockchain_address_transaction_volume_over_time(slug, addresses, from, to, interval)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Blockchain address transaction volume over time",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def transaction_volume_per_address(
        _root,
        %{selector: %{slug: slug} = selector, from: from, to: to, addresses: addresses},
        _resolution
      ) do
    Transfers.blockchain_address_transaction_volume(slug, addresses, from, to)
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Transaction volume per address",
        inspect(selector),
        error,
        description: "selector"
      )
    end)
  end

  def transaction_volume_per_address(_root, _args, _resolution) do
    {:error,
     "Transaction volume per address is currently supported only for selectors with infrastructure ETH and a slug"}
  end

  def incoming_transfers_summary(
        _root,
        %{slug: slug, address: address, page: page, page_size: page_size, from: from, to: to},
        _resolution
      ) do
    opts = [page: page, page_size: page_size]
    Sanbase.Transfers.incoming_transfers_summary(slug, address, from, to, opts)
  end

  def outgoing_transfers_summary(
        _root,
        %{slug: slug, address: address, page: page, page_size: page_size, from: from, to: to},
        _resolution
      ) do
    opts = [page: page, page_size: page_size]
    Sanbase.Transfers.outgoing_transfers_summary(slug, address, from, to, opts)
  end

  def recent_transactions(
        _root,
        %{address: address, type: type, only_sender: only_sender} = args,
        _resolution
      ) do
    %{page: page, page_size: page_size} = args_to_page_args(args)

    # Only Eth and Erc20 are possible here, so the Label.add_labels call has
    # ethereum explicitly set as the blockchain. Same for infrastructure
    infr = "ETH"
    module = @recent_transactions_type_map[type].module
    opts = [page: page, page_size: page_size, only_sender: only_sender]

    with {:ok, transfers} <- module.recent_transactions(address, opts),
         {:ok, transfers} <- BlockchainAddressUtils.transform_address_to_map(transfers, infr),
         {:ok, transfers} <- Label.add_labels("ethereum", transfers),
         {:ok, transfers} <- Sanbase.MarkExchanges.mark_exchanges(transfers) do
      {:ok, transfers}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Recent transactions", %{address: address}, error)}
    end
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
            BlockchainAddressUserPair.create(address, infrastructure, current_user.id)

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
    with {:ok, pair} <- BlockchainAddressUserPair.by_selector(selector, current_user.id),
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

  def add_blockchain_address_labels(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with :ok <-
           Sanbase.Labels.Api.add_labels_to_address(current_user.id, args.address, args.labels) do
      {:ok, true}
    end
    |> maybe_handle_graphql_error(fn error ->
      handle_graphql_error(
        "Add labels for blockchain address",
        args.address,
        error,
        description: "address"
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

          labels =
            (user_labels ++ santiment_labels)
            |> Enum.sort_by(& &1.name)

          {:ok, labels}
        end)
    end
  end

  def infrastructure(root, _args, %{context: %{loader: loader}}) do
    case root_to_blockchain_address(root) do
      %{infrastructure: infrastructure} when is_binary(infrastructure) ->
        {:ok, infrastructure}

      %{infrastructure_id: infrastructure_id} ->
        loader
        |> Dataloader.load(SanbaseDataloader, :infrastructure, infrastructure_id)
        |> on_load(fn loader ->
          {:ok, Dataloader.get(loader, SanbaseDataloader, :infrastructure, infrastructure_id)}
        end)
    end
  end

  def balance(root, %{selector: selector}, %{context: %{loader: loader}}) do
    address = root |> root_to_raw_address() |> BlockchainAddress.to_internal_format()

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

  def balance_dominance(root, %{selector: selector}, %{context: %{loader: loader}}) do
    address = root |> root_to_raw_address() |> BlockchainAddress.to_internal_format()

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

  def comments_count(root, _args, %{context: %{loader: loader}}) do
    root_address = root_to_blockchain_address(root)
    id = root_address.id

    loader
    |> Dataloader.load(SanbaseDataloader, :blockchain_addresses_comments_count, id)
    |> on_load(fn loader ->
      count = Dataloader.get(loader, SanbaseDataloader, :blockchain_addresses_comments_count, id)
      {:ok, count || 0}
    end)
  end

  # Private functions

  defp apply_in_page_order_by(transfers, args) do
    order_by = Map.fetch!(args, :in_page_order_by)
    direction = Map.fetch!(args, :in_page_order_by_direction)

    {:ok, Enum.sort_by(transfers, & &1[order_by], direction)}
  end

  defp args_to_page_args(args) do
    page = Map.get(args, :page, 1)
    page_size = Map.get(args, :page_size, 10)
    page_size = Enum.min([page_size, 100])
    page_size = Enum.max([page_size, 1])

    %{page: page, page_size: page_size}
  end

  defp selector_to_address_map_do_not_create(%{address: _, infrastructure: _} = selector),
    do: selector

  defp selector_to_address_map_do_not_create(%{id: id}) do
    case BlockchainAddress.by_id(id) do
      {:ok, %{address: address, infrastructure: %{code: code}}} ->
        %{address: address, infrastructure: code}

      {:error, error} ->
        {:error, error}
    end
  end

  defp root_to_blockchain_address(%{blockchain_address: blockchain_address}),
    do: blockchain_address

  defp root_to_blockchain_address(%{address: _} = blockchain_address),
    do: blockchain_address

  defp root_to_raw_address(%{blockchain_address: %{address: address}}),
    do: address

  defp root_to_raw_address(%{address: address}), do: address
end
