defmodule Sanbase.Clickhouse.Research.Uniswap do
  alias Sanbase.ClickhouseRepo

  def who_claimed() do
    {query, args} = who_claimed_query()

    ClickhouseRepo.query_transform(query, args, fn [_, value] ->
      value
    end)
    |> case do
      {:ok, [cex, other, dex]} ->
        {:ok,
         %{
           centralized_exchanges: cex,
           decentralized_exchanges: dex,
           other_addresses: other
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def value_distribution() do
    {query, args} = value_distribution_query()

    ClickhouseRepo.query_transform(query, args, fn [_, value] ->
      value
    end)
    |> case do
      {:ok, [total_minted, cex, dex, other, dex_trader]} ->
        {:ok,
         %{
           total_minted: total_minted,
           centralized_exchanges: cex,
           decentralized_exchanges: dex,
           other_transfers: other,
           dex_trader: dex_trader
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp value_distribution_query() do
    query = """
    SELECT 'total minted' as exchange_status,
    sum(value)/1e18 as token_value
    FROM erc20_transfers
    PREWHERE (contract = '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984')
      AND (from = '0x090d4613473dee047c3f2706764f49e0821d256e')
    UNION ALL
    SELECT multiIf(hasAny(labels, ['decentralized_exchange']), 'decentralized_exchange',
                hasAny(labels, ['centralized_exchange', 'deposit', 'withdrawal']), 'centralized_exchange',
                hasAny(labels, ['dex_trader']), 'dex_trader', 'other transfers' ) as exchange_status,
        sum(value_transfered_after_claiming) as token_value
    FROM (
    SELECT
        address,
        splitByChar(',', dictGetString('default.eth_label_dict', 'labels', tuple(cityHash64(address), toUInt64(0)))) as labels,
        if(value_transfered>value_claimed, value_claimed, value_transfered) as value_transfered_after_claiming
    FROM(
        SELECT
            from as address,
            sum(value)/1e18  as value_transfered
        FROM erc20_transfers
        PREWHERE contract = '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984'
              AND dt >= toDateTime('2020-09-16 21:32:52')
        GROUP BY address)
    GLOBAL ALL INNER JOIN (
        SELECT
            to as address,
            sum(value)/1e18 as value_claimed
        FROM erc20_transfers
        PREWHERE (contract = '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984')
              AND (from = '0x090d4613473dee047c3f2706764f49e0821d256e')
        GROUP BY address)
    USING address
    )
    GROUP BY exchange_status
    """

    {query, []}
  end

  defp who_claimed_query() do
    query = """
    SELECT exchange_status, sum(value_) as value__
    FROM (
        SELECT splitByChar(',', dictGetString('default.eth_label_dict', 'labels', tuple(cityHash64(to), toUInt64(0)))) as labels,
              multiIf(hasAny(labels, ['decentralized_exchange']), 'decentralized_exchange',
                      hasAny(labels, ['centralized_exchange', 'deposit', 'withdrawal']), 'centralized_exchange',
                      'other addresses' ) as exchange_status,
              value/1e18 as value_
        FROM erc20_transfers
        PREWHERE (contract = '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984')
            AND (from = '0x090d4613473dee047c3f2706764f49e0821d256e'))
    GROUP BY exchange_status
    ORDER BY value__ DESC
    """

    {query, []}
  end
end
