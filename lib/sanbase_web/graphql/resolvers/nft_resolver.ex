defmodule SanbaseWeb.Graphql.Resolvers.NftResolver do
  @moduledoc false
  alias Sanbase.Clickhouse.NftTrade

  def get_nft_trades(
        _root,
        %{
          from: from,
          to: to,
          label_key: label_key,
          page: page,
          page_size: page_size,
          order_by: order_by,
          direction: direction
        },
        _resolution
      ) do
    opts = [page: page, page_size: page_size, order_by: order_by, direction: direction]
    NftTrade.get_trades(label_key, from, to, opts)
  end

  def get_nft_trades_count(_root, %{from: from, to: to, label_key: label_key}, _resolution) do
    NftTrade.get_trades_count(label_key, from, to)
  end

  def get_nft_collection_by_contract(_root, %{selector: %{address: contract} = selector}, _) do
    infrastructure = selector[:infrastructure] || "ETH"

    case NftTrade.nft_collection_by_contract(contract, infrastructure) do
      nft_collection when is_binary(nft_collection) -> {:ok, %{nft_collection: nft_collection}}
      nil -> {:error, "Can't fetch nft collection name by this contract: #{contract}"}
    end
  end
end
