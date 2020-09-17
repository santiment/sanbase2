defmodule Sanbase.Clickhouse.Fees do
  alias Sanbase.ClickhouseRepo

  def eth_fees_distribution(from, to, limit) do
    {query, args} = eth_fees_distribution_query(from, to, limit)

    ClickhouseRepo.query_transform(query, args, fn [asset, fees] ->
      %{
        asset: asset,
        fees: fees
      }
    end)
  end

  defp eth_fees_distribution_query(from, to, limit) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    query = """
    SELECT
      multiIf(contract = '', 'ethereum',isNull(name), contract, name) AS asset,
      fees
    FROM
    (
        SELECT name, contract, fees
        FROM
        (
            SELECT assetRefId, contract, sum(value) / 1e18 AS fees
            FROM
            (
                SELECT transactionHash, value
                FROM eth_transfers FINAL
                PREWHERE dt >= toDateTime(?1) and dt <= toDateTime(?2)
                WHERE type = 'fee'
            )
            ANY LEFT JOIN
            (
                SELECT transactionHash, contract, assetRefId
                FROM erc20_transfers_union
                WHERE dt >= toDateTime(?1) and dt <= toDateTime(?2)
            ) USING (transactionHash)
            GROUP BY assetRefId, contract
            ORDER BY fees DESC
            LIMIT ?3
        )
        ALL LEFT JOIN
        (
            SELECT name, asset_ref_id AS assetRefId
            FROM asset_metadata FINAL
        ) USING (assetRefId)
    ) ORDER BY fees DESC
    """

    {query, [from_unix, to_unix, limit]}
  end
end
