defmodule SanbaseWeb.Graphql.BlockchainAddressType do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  enum :recent_transactions_type do
    value(:eth)
    value(:erc20)
  end

  enum :transfers_summary_order_by do
    value(:transaction_volume)
    value(:transfers_count)
  end

  enum :in_page_order_by_type do
    value(:trx_value)
    value(:datetime)
  end

  input_object :address_selector do
    field(:address, non_null(:string))
    field(:transaction_type, :transaction_type)
  end

  input_object :blockchain_address_selector_input_object do
    field(:id, :id)
    field(:address, :binary_blockchain_address)
    field(:infrastructure, :string)
  end

  object :transfers_summary do
    field(:last_transfer_datetime, non_null(:datetime))
    field(:address, non_null(:string))
    field(:transaction_volume, non_null(:float))
    field(:transfers_count, non_null(:integer))
  end

  object :current_user_blockchain_address_data do
    field(:pair_id, :integer)
    field(:notes, :string)
    field(:labels, list_of(:blockchain_address_label))
  end

  object :blockchain_address_user_pair do
    field(:id, :integer)
    field(:notes, :string)
    field(:labels, list_of(:blockchain_address_label))
    field(:blockchain_address, :blockchain_address_db_stored)
    field(:user, :user)
  end

  object :blockchain_address_label do
    field(:name, :string)
    field(:human_readable_name, :string)
    field(:notes, :string)
    field(:origin, :string, default_value: "user")
    field(:metadata, :json, default_value: %{})
  end

  object :blockchain_address_label_change do
    field(:address, non_null(:blockchain_address_ephemeral))
    field(:datetime, non_null(:datetime))
    field(:label, non_null(:string))
    field(:sign, non_null(:integer))
  end

  object :current_user_address_details do
    # current user origin labels
    field(:labels, non_null(list_of(:label)))
    field(:watchlists, list_of(:address_watchlist_subtype))
    field(:notes, :string)
  end

  @desc ~s"""
  Represents a blockchain address that is not stored in the postgres database.
  Only data that is available in Clickhouse can be fetched. This type is returned
  as the result of the functions that fetch their data from Clickhouse. This type
  is not used for representing data stored in postgres and by extend it does not
  represent the data in the watchlists, the blockchain address user pairs, etc.
  For these types see the `blockchain_address_db_stored` type.
  """
  object :blockchain_address_ephemeral do
    # santiment origin labels
    field(:is_exchange, :boolean)
    field(:labels, non_null(list_of(:label)))
    field(:address, non_null(:binary_blockchain_address))
    field(:infrastructure, non_null(:string))

    field :current_user_address_details, :current_user_address_details do
      resolve(&BlockchainAddressResolver.current_user_address_details/3)
    end
  end

  object :blockchain_address_db_stored do
    field(:id, non_null(:integer))
    field(:address, non_null(:binary_blockchain_address))

    field :infrastructure, :string do
      cache_resolve(&BlockchainAddressResolver.infrastructure/3)
    end

    @desc ~s"""
    The list of current labels for this address. If the address has had a label
    in the past, but no longer does, the label will not be in the list.
    """
    field :labels, list_of(:blockchain_address_label) do
      cache_resolve(&BlockchainAddressResolver.labels/3)
    end

    field(:notes, :string)

    @desc ~s"""
    The current on-chain amount of the specified token/coin that the address has.
    """
    field :balance, :float do
      arg(:selector, non_null(:historical_balance_selector))
      cache_resolve(&BlockchainAddressResolver.balance/3)
    end

    @desc ~s"""
    What percentage of the total balance of the whole watchlist of a specific
    coin/token a given address holds. If there are no other addresses in the watchlist
    or the field is not executed in the context of a watchlist, 1.0 is returned.
    """
    field :balance_dominance, :float do
      arg(:selector, non_null(:historical_balance_selector))
      cache_resolve(&BlockchainAddressResolver.balance_dominance/3)
    end

    @desc ~s"""
    How the balance of the specified token/coin has changed in the from-to range.
    """
    field :balance_change, :address_balance_change do
      arg(:selector, non_null(:historical_balance_selector))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&BlockchainAddressResolver.balance_change/3)
    end

    field :comments_count, :integer do
      resolve(&BlockchainAddressResolver.comments_count/3)
    end
  end
end
