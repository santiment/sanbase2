defmodule Sanbase.Clickhouse.Research.Uniswap do
  alias Sanbase.ClickhouseRepo

  alias Sanbase.Utils.Config

  alias Sanbase.Transfers.Erc20Transfers
  defp address_ordered_table(), do: Config.module_get(Erc20Transfers, :address_ordered_table)
  defp dt_ordered_table(), do: Config.module_get(Erc20Transfers, :address_ordered_table)

  def who_claimed() do
    {query, args} = who_claimed_query()

    ClickhouseRepo.query_transform(query, args, fn [k, v] -> {k, v} end)
    |> case do
      {:ok, pairs_list} ->
        {:ok, Map.new(pairs_list, fn {k, v} -> {String.to_existing_atom(k), v} end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def value_distribution() do
    {query, args} = value_distribution_query()

    ClickhouseRepo.query_transform(query, args, fn [k, v] -> {k, v} end)
    |> case do
      {:ok, pairs_list} ->
        {:ok, Map.new(pairs_list, fn {k, v} -> {String.to_existing_atom(k), v} end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp value_distribution_query() do
    query = """
    SELECT
      'total_minted' AS exchange_status,
      sum(value)/1e18 AS token_value
    FROM #{address_ordered_table()} FINAL
    PREWHERE
      assetRefId = (SELECT asset_ref_id FROM asset_metadata FINAL WHERE name = 'uniswap' LIMIT 1) AND
      from = '0x090d4613473dee047c3f2706764f49e0821d256e'

    UNION ALL

    SELECT multiIf(
                  hasAny(labels, ['decentralized_exchange']), 'decentralized_exchanges',
                  hasAny(labels, ['centralized_exchange', 'deposit']), 'centralized_exchanges',
                  hasAll(labels, ['withdrawal', 'dex_trader']), 'cex_dex_trader',
                  hasAny(labels, ['withdrawal']), 'cex_trader',
                  hasAny(labels, ['dex_trader']), 'dex_trader',
                  'other_transfers'
      ) AS exchange_status,
      sum(value_transfered_after_claiming) AS token_value
    FROM (
      SELECT
        address,
        splitByChar(',', dictGetString('default.eth_label_dict', 'labels', tuple(cityHash64(address), toUInt64(0)))) AS labels,
        if(value_transfered>value_claimed, value_claimed, value_transfered) AS value_transfered_after_claiming

      FROM(
          SELECT
            from AS address,
            sum(value)/1e18 AS value_transfered
          FROM #{dt_ordered_table()} FINAL
          PREWHERE
            assetRefId = cityHash64('ETH_' || '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984') AND
            dt >= toDateTime('2020-09-16 21:32:52')
          GROUP BY address)
      GLOBAL ALL INNER JOIN (
          SELECT
            to AS address,
            sum(value)/1e18 AS value_claimed
          FROM #{address_ordered_table()} FINAL
          PREWHERE
            assetRefId = cityHash64('ETH_' || '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984') AND
            from = '0x090d4613473dee047c3f2706764f49e0821d256e'
          GROUP BY address)
      USING address
    )
    GROUP BY exchange_status
    """

    {query, []}
  end

  defp who_claimed_query() do
    query = """
    SELECT exchange_status, sum(value2) AS value3
    FROM (
      SELECT
        splitByChar(',', dictGetString('default.eth_label_dict', 'labels', tuple(cityHash64(to), toUInt64(0)))) AS labels,
        multiIf(
                hasAny(labels, ['decentralized_exchange']), 'decentralized_exchanges',
                hasAny(labels, ['centralized_exchange', 'deposit']), 'centralized_exchanges',
                hasAny(labels, ['withdrawal']), 'cex_trader',
                'other_addresses'
        ) AS exchange_status,
        value/1e18 AS value2
      FROM #{address_ordered_table()} FINAL
      PREWHERE
        assetRefId = cityHash64('ETH_' || '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984') AND
        from = '0x090d4613473dee047c3f2706764f49e0821d256e'
    )
    GROUP BY exchange_status
    ORDER BY value3 DESC
    """

    {query, []}
  end
end
