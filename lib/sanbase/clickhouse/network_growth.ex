defmodule Sanbase.Clickhouse.NetworkGrowth do
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def network_growth(contract, from, to, interval) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval)

    query = """
    SELECT toUnixTimestamp(time) as dt, SUM(value) as new_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
        toUInt32(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, sum(total_addresses) as value
      FROM eth_network_growth
      PREWHERE contract = ?3 and
      dt >= toDateTime(?4) and
      dt <= toDateTime(?5)
      group by time
    )
    group by dt
    order by dt
    """

    args = [interval, span, contract, from_datetime_unix, to_datetime_unix]

    ClickhouseRepo.query_transform(query, args, fn [dt, new_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        new_addresses: new_addresses
      }
    end)
  end
end
