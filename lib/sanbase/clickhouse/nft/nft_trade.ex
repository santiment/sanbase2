defmodule Sanbase.Clickhouse.NftTrade do
  def get_trades(label_key, from, to, opts)
      when label_key in [:nft_influencer, :nft_whale] do
    {query, args} = get_trades_query(label_key, from, to, opts)

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
      fn [unix, amount, slug, trx_hash, buyer, seller, nft_contract_address, platform, type] ->
        %{
          datetime: DateTime.from_unix!(unix),
          slug: slug,
          from_address: %{
            address: seller,
            label_key: if("sell" in type, do: label_key)
          },
          to_address: %{
            address: buyer,
            label_key: if("buy" in type, do: label_key)
          },
          amount: amount,
          trx_hash: trx_hash,
          marketplace: platform,
          nft: %{contract_address: nft_contract_address}
        }
      end
    )
  end

  defp get_trades_query(label_key, from, to, opts) do
    nft_influences_subquery = """
    (
      SELECT address
      FROM label_addresses
      WHERE label_id in (SELECT label_id from label_metadata where key = ?3)
    )
    """

    order_key =
      case Keyword.get(opts, :order_by, :datetime) do
        :datetime -> "dt"
        :amount -> "amount"
      end

    query = """
    SELECT dt,
           any(buyer_address) AS buyer_address,
           any(seller_address) AS seller_address,
           amount,
           any(platform) AS platform,
           any(nft_contract_address) AS nft_contract_address,
           any(asset_ref_id) AS asset_ref_id,
           tx_hash,
           groupArray(type) AS type
    FROM (
      SELECT
        toUnixTimestamp(dt) AS dt,
        toUInt64(amount) AS amount,
        tx_hash,
        buyer_address,
        seller_address,
        nft_contract_address,
        asset_ref_id,
        platform,
        'buy' AS type
      FROM nft_trades nft
      JOIN #{nft_influences_subquery} lbl
      ON buyer_address = lbl.address
      WHERE dt >= toDateTime(?1) and dt < toDateTime(?2) AND complete = 1

      UNION ALL

      SELECT
        toUnixTimestamp(dt) AS dt,
        toUInt64(amount) AS amount,
        tx_hash,
        buyer_address,
        seller_address,
        nft_contract_address,
        asset_ref_id,
        platform,
        'sell' AS type
      FROM nft_trades nft
      JOIN #{nft_influences_subquery} lbl
      ON seller_address = lbl.address
      WHERE dt >= toDateTime(?1) and dt < toDateTime(?2) AND complete = 1
    )
    GROUP BY tx_hash, dt, amount
    ORDER BY #{order_key} DESC
    LIMIT ?4 OFFSET ?5
    """

    query = """
    SELECT
      dt,
      amount / pow(10, decimals) AS amount,
      name,
      tx_hash,
      buyer_address,
      seller_address,
      nft_contract_address,
      platform,
      type

    FROM (#{query})

    INNER JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)
    """

    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    args = [
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      to_string(label_key),
      limit,
      offset
    ]

    {query, args}
  end
end
