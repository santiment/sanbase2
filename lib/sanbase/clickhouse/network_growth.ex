defmodule Sanbase.Clickhouse.NetworkGrowth do
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  alias Sanbase.DateTimeUtils

  def network_growth(contract, from, to, interval) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.str_to_sec(interval)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT
      toUnixTimestamp(time) AS dt,
      SUM(new_addresses) AS new_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
        toUInt32(0) AS new_addresses
      FROM numbers(?2)

      UNION ALL

      SELECT
        toDateTime(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
        SUM(value) AS new_addresses
      FROM eth_network_growth
      PREWHERE
        contract = ?3 AND
        dt >= toDate(toDateTime(?4)) AND
        dt <= toDate(toDateTime(?5))
      GROUP BY time
    )
    GROUP BY dt
    ORDER BY dt
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
