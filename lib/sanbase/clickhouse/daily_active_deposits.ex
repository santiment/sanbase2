defmodule Sanbase.Clickhouse.DailyActiveDeposits do
  @moduledoc ~s"""
  Uses ClickHouse to calculate daily active deposits.
  The number of unique deposit addresses that have been active
  """

  use Ecto.Schema

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Math, only: [to_integer: 1]

  alias Sanbase.DateTimeUtils

  @table "daily_active_deposits"
  schema @table do
    field(:dt, :utc_datetime)
    field(:contract, :string)
    field(:exchange, :string)
    field(:total_addresses, :integer)
  end

  @type active_deposits :: %{
          datetime: DateTime.t(),
          active_deposits: non_neg_integer()
        }

  @spec active_deposits(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(active_deposits)} | {:error, String.t()}
  def active_deposits(contract, from, to, interval) do
    {query, args} = active_deposits_query(contract, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, active_deposits] ->
      %{
        datetime: DateTime.from_unix!(dt),
        active_deposits: active_deposits |> to_integer()
      }
    end)
  end

  defp active_deposits_query(contract, from, to, interval) do
    contract = String.downcase(contract)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT
      toUnixTimestamp(time) AS time,
      SUM(value) AS active_deposits
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
        toUInt32(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT
        toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        SUM(total_addresses) AS value
      FROM #{@table}
      PREWHERE
        contract = ?3 AND
        dt >= toDateTime(?4) AND
        dt <= toDateTime(?5)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, contract, from_datetime_unix, to_datetime_unix]

    {query, args}
  end
end
