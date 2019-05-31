defmodule Sanbase.Clickhouse.TokenCirculation do
  @moduledoc ~s"""
  Token circulation shows the distribution of non-transacted tokens over time.
  In other words - how many tokens are being HODLed, and for how long.

  Practical example:
  In one particular day Alice sends 20 ETH to Bob, Bob sends 10 ETH to Charlie
  and Charlie sends 5 ETH to Dean. This corresponds to the amount of tokens that have
  been HODLed for less than 1 day ("_-1d" column in the table)
  ###
     Alice  -- 20 ETH -->  Bob
                            |
                          10 ETH
                            |
                            v
     Dean <-- 5  ETH -- Charlie
  ###

  In this scenario the transaction volume is 20 + 10 + 5 = 35 ETH, though the ETH
  in circulation is 20 ETH.

  This can be explained as having twenty $1 bills. Alice sends all of them to Bob,
  Bob sends 10 of the received bills to Charlie and Charlie sends 5 of them to Dean.

  One of the most useful properities of Token Circulation is that this metric is immune
  to mixers and gives a much better view of the actual amount of tokens that are being
  transacted
  """

  @typedoc ~s"""
  Returned by the `token_circulation/6` and `token_circulation!/6` functions.
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "daily_metrics"
  @metric_name "circulation_1d"

  @type circulation_map :: %{
          datetime: %DateTime{},
          token_circulation: float()
        }

  @spec changeset(any(), any()) :: no_return
  def changeset(_, _) do
    raise "Cannot change daily metrics ClickHouse table!"
  end

  @doc ~s"""
  Return the token circulation for a given contract and time restrictions.
  Currently supports only the token circulation for less than a day.
  """
  @spec token_circulation(
          :less_than_a_day,
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t()
        ) :: {:ok, list(circulation_map)} | {:error, String.t()}
  def token_circulation(:less_than_a_day, ticker_slug, from, to, interval) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)

    case rem(interval, 86_400) do
      0 ->
        calculate_token_circulation(
          :less_than_a_day,
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

  defp calculate_token_circulation(
         :less_than_a_day,
         ticker_slug,
         from,
         to,
         interval
       ) do
    {query, args} = token_circulation_query(:less_than_a_day, ticker_slug, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [timestamp, token_circulation] ->
        %{
          datetime: timestamp |> DateTime.from_unix!(),
          token_circulation: token_circulation
        }
      end
    )
  end

  defp token_circulation_query(:less_than_a_day, ticker_slug, from, to, interval) do
    query = """
    SELECT
      toUnixTimestamp((intDiv(toUInt32(toDateTime(dt2)), ?1) * ?1)) AS ts,
      AVG(value)
    FROM (
      SELECT
        toDateTime(dt) AS dt2,
        argMax(value,computed_at) AS value
      FROM
        #{@table}
      PREWHERE
        dt >= toDate(?2) AND
        dt <= toDate(?3) AND
        ticker_slug = ?4 AND
        metric = '#{@metric_name}'
      GROUP BY dt2
    )
    GROUP BY ts
    ORDER BY ts
    """

    args = [interval, from, to, ticker_slug]

    {query, args}
  end
end
