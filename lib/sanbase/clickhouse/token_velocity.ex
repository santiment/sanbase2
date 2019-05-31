defmodule Sanbase.Clickhouse.TokenVelocity do
  @moduledoc ~s"""
  Token Velocity is a metric which estimates the average frequency
  at which the tokens change hands during some period of time.

  Example:
  * Alice gives Bob 10 tokens at block 1 and
  * Bob gives Charlie 10 tokens at block 2

  The total transaction volume which is generated for block 1 and 2 is `10 + 10 = 20`
  The tokens being in circulation is actually `10` - because the same 10 tokens have been transacted.
  Token Velocity for blocks 1 and 2 is `20 / 10 = 2`
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "daily_metrics"
  @circulation_metric_name "circulation_1d"
  @trx_volume_metric_name "transaction_volume"

  @type velocity_map :: %{
          datetime: %DateTime{},
          token_velocity: float()
        }

  @spec changeset(any(), any()) :: no_return
  def changeset(_, _) do
    raise "Cannot change daily metrics ClickHouse table!"
  end

  @doc ~s"""
  Return the token velocity for a given slug and time restrictions.
  Token velocity for a given interval is calculatied by dividing the transaction
  volume by the circulation
  """
  @spec token_velocity(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(velocity_map)} | {:error, String.t()}
  def token_velocity(ticker_slug, from, to, interval) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)

    case rem(interval, 86_400) do
      0 ->
        calculate_token_velocity(
          ticker_slug,
          from,
          to,
          interval
        )

      _ ->
        {:error, "The interval must consist of whole days!"}
    end
  end

  def first_datetime(ticker_slug) do
    query = """
    SELECT
      toUnixTimestamp(min(dt))
    FROM #{@table}
    PREWHERE
      ticker_slug = ?1
    """

    ClickhouseRepo.query_transform(query, [ticker_slug], fn [datetime] ->
      datetime |> DateTime.from_unix!()
    end)
    |> case do
      {:ok, [first_datetime]} -> {:ok, first_datetime}
      error -> error
    end
  end

  # Private functions

  defp calculate_token_velocity(
         ticker_slug,
         from,
         to,
         interval
       ) do
    {query, args} = token_velocity_query(ticker_slug, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [timestamp, token_velocity] ->
        %{
          datetime: timestamp |> DateTime.from_unix!(),
          token_velocity: token_velocity
        }
      end
    )
  end

  defp token_velocity_query(ticker_slug, from, to, interval) do
    query = """
    SELECT
      toUnixTimestamp((intDiv(toUInt32(toDateTime(dt2)), ?1) * ?1)) AS ts,
      AVG(token_velocity)
      FROM (
        SELECT
          dt2 AS dt2,
          transaction_volume / circulation_1d AS token_velocity
        FROM (
          SELECT
            toDateTime(dt) AS dt2,
            argMaxIf(value, computed_at, metric = '#{@circulation_metric_name}') AS circulation_1d,
            argMaxIf(value, computed_at, metric = '#{@trx_volume_metric_name}') AS transaction_volume
          FROM
            #{@table}
          PREWHERE
            dt >= toDateTime(?2) AND
            dt <= toDateTime(?3) AND
            metric IN ('#{@circulation_metric_name}', '#{@trx_volume_metric_name}') AND
            ticker_slug = ?4
          GROUP BY dt2
        )
        ORDER BY dt2
      )
    GROUP BY ts
    ORDER BY ts
    """

    args = [interval, from, to, ticker_slug]

    {query, args}
  end
end
