defmodule Sanbase.Clickhouse.NetworkGrowth do
  @moduledoc ~s"""
  Uses ClickHouse to calculate Network growth - number of new addresses being
  created on the network.
  """
  alias Sanbase.DateTimeUtils
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type network_growth :: %{
          datetime: %DateTime{},
          new_addresses: integer
        }

  @spec network_growth(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(network_growth)} | {:error, String.t()}
  def network_growth(contract, from, to, interval) do
    {query, args} = network_growth_query(contract, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, new_addresses] ->
      %{
        datetime: DateTime.from_unix!(dt),
        new_addresses: new_addresses
      }
    end)
  end

  defp network_growth_query(contract, from, to, interval) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT
      toUnixTimestamp(time) AS dt,
      SUM(value) AS new_addresses
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
        toUInt32(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT
        toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        sum(total_addresses) AS value
      FROM eth_network_growth
      PREWHERE contract = ?3 AND
      dt >= toDateTime(?4) AND
      dt <= toDateTime(?5)
      GROUP BY time
    )
    GROUP BY dt
    ORDER BY dt
    """

    args = [interval, span, contract, from_datetime_unix, to_datetime_unix]
    {query, args}
  end
end
