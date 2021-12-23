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
      fn list ->
        [
          ts,
          amount,
          amount_tokens,
          slug,
          trx_hash,
          buyer_address,
          seller_address,
          nft_contract_address,
          nft_contract_name,
          platform,
          type,
          price_usd
        ] = list

        %{
          datetime: DateTime.from_unix!(ts),
          slug: slug,
          from_address: %{
            address: seller_address,
            label_key: if("sell" in type, do: label_key)
          },
          to_address: %{
            address: buyer_address,
            label_key: if("buy" in type, do: label_key)
          },
          amount: amount,
          quantity: amount_tokens |> List.first() |> Sanbase.Math.to_float(),
          trx_hash: trx_hash,
          marketplace: platform,
          nft: %{contract_address: nft_contract_address, name: nft_contract_name},
          price_usd: price_usd
        }
      end
    )
  end

  defp get_trades_count_query(label_key, from, to) do
    query = """
    SELECT count(*)
    FROM (
      SELECT dt, log_index
      FROM (#{label_key_dt_filtered_subquery(from_arg_position: 1, to_arg_position: 2, label_key_arg_position: 3)})
      GROUP BY dt, log_index
    )
    """

    args = [DateTime.to_unix(from), DateTime.to_unix(to), to_string(label_key)]

    {query, args}
  end

  defp get_trades_query(label_key, from, to, opts) do
    order_key =
      case Keyword.fetch!(opts, :order_by) do
        :datetime -> "dt"
        :amount -> "price_usd"
      end

    direction =
      case Keyword.fetch!(opts, :direction) do
        :asc -> "ASC"
        :desc -> "DESC"
      end

    query = """
    SELECT dt,
           log_index,
           argMax(buyer_address, computed_at) AS buyer_address,
           argMax(seller_address, computed_at) AS seller_address,
           argMax(amount, computed_at) AS amount,
           argMax(amount_tokens, computed_at) AS amount_tokens,
           argMax(platform, computed_at) AS platform,
           argMax(nft_contract_address, computed_at) AS nft_contract_address,
           argMax(nft_contract_name, computed_at) AS nft_contract_name,
           argMax(asset_ref_id, computed_at) AS asset_ref_id,
           argMax(tx_hash, computed_at) as tx_hash,
           groupArray(type) AS type
    FROM (#{label_key_dt_filtered_subquery(from_arg_position: 1, to_arg_position: 2, label_key_arg_position: 3)})
    GROUP BY dt, log_index
    """

    # Note: In CH left join if the right hand record in assets table
    # doesn't exists fills decimals with default value 0.
    # Since 0 is a valid value for decimals the check `isNull(name)` is used to check whether
    # right record in assets table exists. If it doesn't exists - replace the decimals with `18`.
    query = """
    SELECT dt, amount / pow(10, if(isNull(name), 18, decimals)) AS amount, amount_tokens, name, tx_hash, buyer_address, seller_address, nft_contract_address, nft_contract_name, platform, type,
      if(
          prices.price_usd != 0,
          prices.price_usd * toFloat64(amount) / pow(10, decimals),
          current_prices.price_usd * toFloat64(amount) / pow(10, decimals)
      ) as price_usd
    SELECT *

    FROM (#{query}) as trades

    LEFT JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) as assets
    ON trades.asset_ref_id = assets.asset_ref_id

    LEFT JOIN (
      SELECT asset_id, value AS price_usd, dt
      FROM intraday_metrics
      WHERE
        metric_id = (SELECT metric_id FROM metric_metadata WHERE name = 'price_usd')
        AND dt >= toDateTime(?#{from}) and dt < toDateTime(?#{to})
    ) as prices
    ON toStartOfFiveMinute(trades.dt) = prices.dt AND assets.asset_id = prices.asset_id

    LEFT JOIN (
      SELECT slug, price_usd, dt
      FROM asset_prices_v3
      WHERE
        dt < toDateTime(?#{to})
        dt >= (
          SELECT dt
          FROM intraday_metrics
          WHERE
            metric_id = (SELECT metric_id FROM metric_metadata WHERE name = 'price_usd')
            AND dt >= toDateTime(?#{from}) and dt < toDateTime(?#{to})
            ORDER BY dt desc
            LIMIT 1
        )
        dt >= toDateTime('2021-12-31 00:00:00')
      ORDER BY dt desc, source desc
    ) AS current_prices
    ON prices.price_usd = 0 AND toStartOfFiveMinute(trades.dt) = toStartOfFiveMinute(current_prices.dt) AND assets.name = current_prices.slug

    ORDER BY #{order_key} #{direction}
    LIMIT ?4 OFFSET ?5
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

    combined_buyer_seller = """
    SELECT toUnixTimestamp(dt) AS dt, log_index, amount_tokens, toFloat64(amount) AS amount, tx_hash, buyer_address, seller_address, nft_contract_address, asset_ref_id, platform, 'buy' AS type, computed_at
    FROM nft_trades nft
    JOIN #{nft_influences_subquery} lbl
    ON buyer_address = lbl.address
    WHERE dt >= toDateTime(?#{from_arg_position}) and dt < toDateTime(?#{to_arg_position}) AND complete = 1

    UNION ALL

    SELECT toUnixTimestamp(dt) AS dt, log_index, amount_tokens, toFloat64(amount) AS amount, tx_hash, buyer_address, seller_address, nft_contract_address, asset_ref_id, platform, 'sell' AS type, computed_at
    FROM nft_trades nft
    JOIN #{nft_influences_subquery} lbl
    ON seller_address = lbl.address
    WHERE dt >= toDateTime(?#{from_arg_position}) and dt < toDateTime(?#{to_arg_position}) AND complete = 1
    """

    _joined_nft_contract_name = """
    SELECT  dt, log_index, amount_tokens, amount, tx_hash, buyer_address, seller_address, nft_contract_address, nft_contract_name, asset_ref_id, platform, type, computed_at
    FROM ( #{combined_buyer_seller} )
    LEFT JOIN (
      SELECT
        address AS nft_contract_address,
        name AS nft_contract_name
      FROM
      (
        SELECT
          address,
          label_id
        FROM current_label_addresses
        WHERE
          label_id in (SELECT label_id from label_metadata where key='name')
          AND address IN (SELECT address FROM label_addresses WHERE label_id IN (SELECT label_id FROM label_metadata WHERE key = 'nft'))
      )
      LEFT JOIN
      (
        SELECT
          label_id,
          value as name
        FROM label_metadata
      ) USING (label_id)
    ) USING (nft_contract_address)
    """
  end
end
