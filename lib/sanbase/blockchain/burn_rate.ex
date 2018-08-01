defmodule Sanbase.Blockchain.BurnRate do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Timescaledb

  alias __MODULE__
  @primary_key false
  schema "eth_burn_rate" do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:burn_rate, :float)
  end

  def changeset(burn_rate, attrs \\ %{}) do
    burn_rate
    |> cast(attrs, [:timestamp, :contract_address, :burn_rate])
    |> validate_number(:burn_rate, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  defp burn_rate_query(contract, from, to, interval) do
    seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    interval = %Postgrex.Interval{secs: seconds}

    from(
      br in __MODULE__,
      where: br.timestamp > ^from and br.timestamp < ^to and br.contract_address == ^contract,
      select: %{
        datetime: time_bucket(^interval),
        burn_rate: sum(br.burn_rate)
      },
      order_by: time_bucket(),
      group_by: time_bucket()
    )
  end

  def burn_rate(contract, from, to, interval) do
    burn_rate_query(contract, from, to, interval)
    |> Sanbase.TimescaleRepo.all()
  end

  def burn_rate_fill(contract, from, to, interval) do
    interval = %Postgrex.Interval{days: interval}
    query = burn_rate_query(contract, from, to, interval)

    from(
      br in subquery(query),
      right_join: day in generate_series(^from, ^to, ^interval),
      on: day.d == br.datetime,
      select: %{
        burn_rate: coalesce(br.burn_rate, 0),
        datetime: day.d
      }
    )
    |> Sanbase.TimescaleRepo.all()
  end

  def burn_rate2(contract, from, to, interval) do
    seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    interval = %Postgrex.Interval{secs: seconds}

    query = """
    WITH
      data AS (
        SELECT
            time_bucket($1::interval, timestamp)::timestamp AS ts,
            sum(burn_rate) AS burn_rate
          FROM eth_burn_rate
          WHERE timestamp >= $2 AND timestamp <= $3 AND contract_address = $4
          GROUP BY ts
      ),
      period AS (
        SELECT ts::timestamp
          FROM generate_series(time_bucket($1, $2), $3, $1) AS ts
      )
    SELECT period.ts, coalesce(data.burn_rate, 0) as burn_rate
      FROM period
      LEFT JOIN data ON period.ts = data.ts
      ORDER BY period.ts;
    """

    args = [
      interval,
      from,
      to,
      contract
    ]

    Sanbase.TimescaleRepo.query(query, args)
  end

  def burn_rate_raw(contract, from, to, interval) do
    interval = %Postgrex.Interval{days: interval}
    sub_query = burn_rate_query(contract, from, to, interval)

    query =
      from(
        br in subquery(sub_query),
        right_join: day in generate_series(^from, ^to, ^interval),
        on: day.d == br.datetime,
        select: br,
        group_by: day.d,
        order_by: day.d
      )

    {query, args} = Ecto.Adapters.SQL.to_sql(:all, Sanbase.TimescaleRepo, query)

    Sanbase.TimescaleRepo.query(query, args)
  end

  def period(%DateTime{} = from, %DateTime{} = to, interval) do
    seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    interval = %Postgrex.Interval{secs: seconds}

    query = """
      SELECT ts::timestamp FROM generate_series($2::timestamp, $3, $1) AS ts
    """

    args = [
      interval,
      from,
      to
    ]

    Sanbase.TimescaleRepo.query(query, args)
  end

  def br(contract, from, to, interval) do
    seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    interval = %Postgrex.Interval{secs: seconds}

    query = """
    SELECT
        time_bucket($1::interval, timestamp)::timestamp AS ts,
        sum(burn_rate) AS burn_rate
      FROM eth_burn_rate
      WHERE timestamp >= $2 AND timestamp <= $3 AND contract_address = $4
      GROUP BY ts
    """

    args = [
      interval,
      from,
      to,
      contract
    ]

    Sanbase.TimescaleRepo.query(query, args)
  end

  #   SELECT time_bucket('2 weeks'::interval / 1080,  no_gaps) btime
end
