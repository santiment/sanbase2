defmodule SanbaseWeb.Graphql.Resolvers.NftResolver do
  def get_nft_trades(
        _root,
        %{
          from: from,
          to: to,
          label_key: label_key,
          page: page,
          page_size: page_size,
          order_by: order_by
        },
        _resolution
      ) do
    opts = [page: page, page_size: page_size, order_by: order_by]
    Sanbase.Clickhouse.NftTrade.get_trades(label_key, from, to, opts)
  end
end
