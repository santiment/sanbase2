defmodule Sanbase.Clickhouse.MiningPoolsDistribution do
  @moduledoc ~s"""
  Uses ClickHouse to calculate distribution of miners between mining pools.
  Currently only ETH is supported. 
  """

  alias Sanbase.DateTimeUtils
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type distribution :: %{
          datetime: DateTime.t(),
          top3: float,
          top10: float,
          other: float
        }

  @spec distribution(
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(distribution)} | {:error, String.t()}
  def distribution(from, to, interval) do
    {query, args} = distribution_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, top3, top10, other] ->
        %{
          datetime: DateTime.from_unix!(dt),
          top3: top3,
          top10: top10,
          other: other
        }
      end
    )
  end

  defp distribution_query(from, to, interval) do
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(date)), ?1) * ?1) AS time,
      maxIf(value, id=5) AS top_3,
      maxIf(value, id=6) AS top_10,
      maxIf(value, id=7) AS other
    FROM eth_miners_metrics
    WHERE
      date >= toDate(?2) AND
      date <= toDate(?3) AND
      id IN (5,6,7)
    GROUP BY time, date
    ORDER BY time ASC
    """

    args = [interval, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
