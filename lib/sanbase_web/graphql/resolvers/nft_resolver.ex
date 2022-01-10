defmodule SanbaseWeb.Graphql.Resolvers.NftResolver do
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
    Sanbase.Clickhouse.NftTrade.get_trades(label_key, from, to, opts)
  end

  def get_nft_trades_count(_root, %{from: from, to: to, label_key: label_key}, _resolution) do
    Sanbase.Clickhouse.NftTrade.get_trades_count(label_key, from, to)
  end
end
