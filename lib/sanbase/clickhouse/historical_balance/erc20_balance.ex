defmodule Sanbase.Clickhouse.HistoricalBalance.Erc20Balance do
  @doc ~s"""
  Returns the historical balances of given address and erc20 contract
  in all intervals between two datetimes.
  """

  use Ecto.Schema

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo
  import Sanbase.Clickhouse.HistoricalBalance.Utils

  @type historical_balance :: %{
          datetime: non_neg_integer(),
          balance: float
        }

  @table "erc20_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _attrs \\ %{}),
    do: raise("Should not try to change eth daily active addresses")

  @spec historical_balance(
          String.t(),
          String.t(),
          non_neg_integer(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:ok, list(historical_balance)} | {:error, String.t()}
  def historical_balance(address, contract, token_decimals, from, to, interval) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)
    address = String.downcase(address)
    contract = String.downcase(contract)

    {query, args} = historical_balance_query(address, contract, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: Sanbase.DateTimeUtils.from_erl!(dt),
        balance: value / token_decimals,
        has_changed: has_changed
      }
    end)
    |> case do
      {:ok, result} ->
        # Clickhouse fills empty buckets with 0 while we need it filled with the last
        # seen value. As the balance changes happen only when a transfer occurs
        # then we need to fetch the whole history of changes in order to find the balance
        result =
          result
          |> fill_gaps_last_seen_balance()
          |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, from) == :lt end)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  def balance_change(address, contract, token_decimals, from, to) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)

    query = """
    SELECT
      argMaxIf(value, dt, dt<=?3 AND sign = 1) as start_balance,
      argMaxIf(value, dt, dt<=?4 AND sign = 1) as end_balance,
      end_balance - start_balance as diff
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      contract = ?2
    """

    args = [address |> String.downcase(), contract, from, to]

    ClickhouseRepo.query_transform(query, args, fn [s, e, value] ->
      {s / token_decimals, e / token_decimals, value / token_decimals}
    end)
  end

  @first_datetime ~N[2015-10-29 00:00:00]
                  |> DateTime.from_naive!("Etc/UTC")
                  |> DateTime.to_unix()
  defp historical_balance_query(address, contract, _from, to, interval) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - @first_datetime, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers(?2)

    UNION ALL

    SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time, argMax(value, dt), toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE address = ?3
      AND contract = ?4
      AND sign = 1
      AND dt <= toDateTime(?6)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      span,
      address,
      contract,
      @first_datetime,
      to_unix
    ]

    {query, args}
  end
end
