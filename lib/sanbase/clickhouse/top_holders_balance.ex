defmodule Sanbase.Clickhouse.TopHolders.Balance do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the percent supply in exchanges, non exchanges and combined
  """

  import Sanbase.DateTimeUtils
  alias Sanbase.Model.Project

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def balance("top_holders_balance" = metric, %{slug: slug, count: count}, from, to, interval) do
    with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug) do
      {query, args} = balance_query(metric, contract, count, from, to, interval, decimals)

      ClickhouseRepo.query_transform(query, args, fn [timestamp, value] ->
        %{datetime: DateTime.from_unix!(timestamp), value: value}
      end)
    end
  end

  defp balance_query("top_holders_balance", contract, count, from, to, interval, decimals) do
    decimals = Sanbase.Math.ipow(10, decimals)

    query = """
    SELECT dt, SUM(value)
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS dt,
        argMax(value, dt) / #{decimals} AS value
      FROM eth_top_holders
      PREWHERE
        contract = ?2 AND
        rank <= ?3 AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5)
      GROUP BY dt, address
    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [
      interval |> str_to_sec(),
      contract,
      count,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end
end
