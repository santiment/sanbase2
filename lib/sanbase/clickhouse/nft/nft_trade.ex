defmodule Sanbase.Clickhouse.NftTrade do
  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  def get_trades_count(label_key, from, to) do
    {query, args} = get_trades_count_query(label_key, from, to)

    Sanbase.ClickhouseRepo.query_transform(query, args, fn [count] -> count end)
    |> maybe_unwrap_ok_value()
  end

  def get_trades(label_key, from, to, opts)
      when label_key in [:nft_influencer, :nft_whale] do
    {query, args} = get_trades_query(label_key, from, to, opts)

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
      fn [ts, amount, slug, trx_hash, buyer, seller, nft_contract_address, platform, type] ->
        %{
          datetime: DateTime.from_unix!(ts),
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

  defp get_trades_count_query(label_key, from, to) do
    query = """
    SELECT count(*)
    FROM (
      SELECT tx_hash
      FROM (#{label_key_dt_filtered_subquery(from_arg_position: 1, to_arg_position: 2, label_key_arg_position: 3)})
      GROUP BY tx_hash
    )
    """

    args = [DateTime.to_unix(from), DateTime.to_unix(to), to_string(label_key)]

    {query, args}
  end

  defp get_trades_query(label_key, from, to, opts) do
    order_key =
      case Keyword.fetch!(opts, :order_by) do
        :datetime -> "dt"
        :amount -> "amount"
      end

    direction =
      case Keyword.fetch!(opts, :direction) do
        :asc -> "ASC"
        :desc -> "DESC"
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
    FROM (#{label_key_dt_filtered_subquery(from_arg_position: 1, to_arg_position: 2, label_key_arg_position: 3)})
    GROUP BY tx_hash, dt, amount
    ORDER BY #{order_key} #{direction}
    LIMIT ?4 OFFSET ?5
    """

    query = """
    SELECT dt, amount / pow(10, decimals) AS amount, name, tx_hash, buyer_address, seller_address, nft_contract_address, platform, type

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

  defp label_key_dt_filtered_subquery(opts) do
    label_key_arg_position = Keyword.fetch!(opts, :label_key_arg_position)
    from_arg_position = Keyword.fetch!(opts, :from_arg_position)
    to_arg_position = Keyword.fetch!(opts, :to_arg_position)

    nft_influences_subquery = """
    (
      SELECT address
      FROM label_addresses
      WHERE label_id in (SELECT label_id from label_metadata where key = ?#{label_key_arg_position})
    )
    """

    """
    SELECT toUnixTimestamp(dt) AS dt, toUInt64(amount) AS amount, tx_hash, buyer_address, seller_address, nft_contract_address, asset_ref_id, platform, 'buy' AS type
      FROM nft_trades nft
      JOIN #{nft_influences_subquery} lbl
      ON buyer_address = lbl.address
      WHERE dt >= toDateTime(?#{from_arg_position}) and dt < toDateTime(?#{to_arg_position}) AND complete = 1

      UNION ALL

      SELECT toUnixTimestamp(dt) AS dt, toUInt64(amount) AS amount, tx_hash, buyer_address, seller_address, nft_contract_address, asset_ref_id, platform, 'sell' AS type
      FROM nft_trades nft
      JOIN #{nft_influences_subquery} lbl
      ON seller_address = lbl.address
      WHERE dt >= toDateTime(?#{from_arg_position}) and dt < toDateTime(?#{to_arg_position}) AND complete = 1
    """
  end
end
