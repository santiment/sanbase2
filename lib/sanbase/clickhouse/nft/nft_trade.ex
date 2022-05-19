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
          token_ids,
          slug,
          trx_hash,
          buyer_address,
          seller_address,
          nft_contract_address,
          nft_contract_name,
          platform,
          type
        ] = list

        quantities =
          Enum.zip(token_ids, amount_tokens)
          |> Enum.map(fn {id, amount} ->
            %{
              token_id: id,
              quantity: Sanbase.Math.to_float(amount)
            }
          end)

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
          quantities: quantities,
          trx_hash: trx_hash,
          marketplace: platform,
          nft: %{contract_address: nft_contract_address, name: nft_contract_name}
        }
      end
    )
  end

  def nft_collection_by_contract(contract, infrastructure \\ "ETH") do
    contract = Sanbase.BlockchainAddress.to_internal_format(contract)
    blockchain = Sanbase.Model.Project.infrastructure_to_blockchain(infrastructure)

    {query, args} = fetch_label_query(contract, blockchain, "value")

    case ClickhouseRepo.query_transform(query, args, fn [label] -> label end) do
      {:ok, [label]} when not is_nil(label) -> label
      _ -> nil
    end
  end

  def nft_search_text_by_contract(contract, infrastructure \\ "ETH") do
    contract = Sanbase.BlockchainAddress.to_internal_format(contract)
    blockchain = Sanbase.Model.Project.infrastructure_to_blockchain(infrastructure)

    {query, args} = fetch_label_query(contract, blockchain, "search_text")

    case ClickhouseRepo.query_transform(query, args, fn [search_term] -> search_term end) do
      {:ok, [search_term]} when not is_nil(search_term) -> search_term
      _ -> nil
    end
  end

  defp fetch_label_query(contract, blockchain, field) do
    query = """
    SELECT dictGet('default.labels_dict', #{field}, label_id)
    FROM
    (
        SELECT labels
        FROM default.current_labels
        WHERE (blockchain = ?1) AND (address = lower(?2))
    )
    ARRAY JOIN labels AS label_id
    WHERE dictGet('default.labels_dict', 'key', label_id) = 'name'
    """

    args = [blockchain, contract]

    {query, args}
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
        :amount -> "amount"
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
           argMax(token_ids, computed_at) AS token_ids,
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
    SELECT
      dt,
      amount / pow(10, if(isNull(name), 18, decimals)) AS amount,
      amount_tokens,
      token_ids,
      name,
      tx_hash,
      buyer_address,
      seller_address,
      nft_contract_address,
      nft_contract_name,
      platform,
      type

    FROM (#{query})

    LEFT JOIN (
      SELECT asset_ref_id, name, decimals
      FROM asset_metadata FINAL
    ) USING (asset_ref_id)

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
    SELECT toUnixTimestamp(dt) AS dt, log_index, amount_tokens, token_ids, toFloat64(amount) AS amount, tx_hash, buyer_address, seller_address, nft_contract_address, asset_ref_id, platform, 'buy' AS type, computed_at
    FROM nft_trades nft
    JOIN #{nft_influences_subquery} lbl
    ON buyer_address = lbl.address
    WHERE dt >= toDateTime(?#{from_arg_position}) and dt < toDateTime(?#{to_arg_position}) AND complete = 1

    UNION ALL

    SELECT toUnixTimestamp(dt) AS dt, log_index, amount_tokens, token_ids, toFloat64(amount) AS amount, tx_hash, buyer_address, seller_address, nft_contract_address, asset_ref_id, platform, 'sell' AS type, computed_at
    FROM nft_trades nft
    JOIN #{nft_influences_subquery} lbl
    ON seller_address = lbl.address
    WHERE dt >= toDateTime(?#{from_arg_position}) and dt < toDateTime(?#{to_arg_position}) AND complete = 1
    """

    _joined_nft_contract_name = """
    SELECT  dt, log_index, amount_tokens, token_ids, amount, tx_hash, buyer_address, seller_address, nft_contract_address, nft_contract_name, asset_ref_id, platform, type, computed_at
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
