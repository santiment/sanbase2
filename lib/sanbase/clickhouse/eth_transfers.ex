defmodule Sanbase.Clickhouse.EthTransfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ETH transfers.
  """

  @type t :: %__MODULE__{
          datetime: %DateTime{},
          from_address: String.t(),
          to_address: String.t(),
          trx_hash: String.t(),
          trx_value: float,
          block_number: non_neg_integer,
          trx_position: non_neg_integer,
          type: String.t()
        }

  @type spent_over_time_type :: %{
          eth_spent: float,
          datetime: %DateTime{}
        }

  @type wallets :: list(String.t())

  use Ecto.Schema

  require Logger
  alias Sanbase.ClickhouseRepo

  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils

  @table "eth_transfers"
  @eth_decimals 1_000_000_000_000_000_000

  @primary_key false
  @timestamps_opts [updated_at: false]
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:from_address, :string, primary_key: true, source: :from)
    field(:to_address, :string, primary_key: true, source: :to)
    field(:trx_hash, :string, source: :transactionHash)
    field(:trx_value, :float, source: :value)
    field(:block_number, :integer, source: :blockNumber)
    field(:trx_position, :integer, source: :transactionPosition)
    field(:type, :string)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _) do
    raise "Should not try to change eth transfers"
  end

  @doc ~s"""
  Return the `limit` biggest transfers for a list of wallets and time period.
  Only transfers which `from` address is in the list and `to` address is
  not in the list are selected.
  """
  @spec top_wallet_transfers(wallets, %DateTime{}, %DateTime{}, integer, String.t()) ::
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def top_wallet_transfers([], _from, _to, _limit, _type), do: {:ok, []}

  def top_wallet_transfers(wallets, from, to, limit, type) do
    {query, args} = wallet_transactions_query(wallets, from, to, limit, type)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: from_address,
          to_address: to_address,
          trx_hash: trx_hash,
          trx_value: trx_value
        }
    end)
  end

  @spec eth_top_transactions(%DateTime{}, %DateTime{}, integer) ::
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def eth_top_transactions(from, to, limit) do
    {query, args} = eth_top_transactions_query(from, to, limit)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: from_address,
          to_address: to_address,
          trx_hash: trx_hash,
          trx_value: trx_value / @eth_decimals
        }
    end)
  end

  @doc ~s"""
  The total ETH spent in the `from` - `to` interval
  """
  @spec eth_spent(wallets, %DateTime{}, %DateTime{}) ::
          {:ok, []} | {:ok, [{String.t(), float()}]} | {:error, String.t()}
  def eth_spent([], _, _), do: {:ok, []}

  def eth_spent(wallets, from, to) do
    {query, args} = eth_spent_query(wallets, from, to)

    ClickhouseRepo.query_transform(query, args, fn [from, value] ->
      {from, value / @eth_decimals}
    end)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Return a list of maps `%{datetime: datetime, eth_spent: ethspent}` that shows
  how much ETH has been spent for the list of `wallets` for each `interval` in the
  time period [`from`, `to`]
  """
  @spec eth_spent_over_time(%Project{} | wallets, %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, list(spent_over_time_type)} | {:error, String.t()}
  def eth_spent_over_time(%Project{} = project, from, to, interval) do
    {:ok, eth_addresses} = Project.eth_addresses(project)
    eth_spent_over_time(eth_addresses, from, to, interval)
  end

  def eth_spent_over_time([], _, _, _), do: {:ok, []}

  def eth_spent_over_time(wallets, from, to, interval) when is_list(wallets) do
    {query, args} = eth_spent_over_time_query(wallets, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [value, datetime_str] ->
      %{
        datetime: datetime_str |> DateTimeUtils.from_erl!(),
        eth_spent: value / @eth_decimals
      }
    end)
  end

  # Private functions

  defp wallet_transactions_query(wallets, from, to, limit, :out) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      value / #{@eth_decimals}
    FROM #{@table} FINAL
    PREWHERE
      from IN (?1) AND
      NOT to IN (?1) AND
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3) AND
      type = 'call'
    ORDER BY value DESC
    LIMIT ?4
    """

    args = [
      wallets,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      limit
    ]

    {query, args}
  end

  defp wallet_transactions_query(wallets, from, to, limit, :in) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      value / #{@eth_decimals}
    FROM #{@table} FINAL
    PREWHERE
      from NOT IN (?1) AND
      to IN (?1) AND
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3) AND
      type = 'call'
    ORDER BY value DESC
    LIMIT ?4
    """

    args = [
      wallets,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      limit
    ]

    {query, args}
  end

  defp wallet_transactions_query(wallets, from, to, limit, :all) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      value / #{@eth_decimals}
    FROM #{@table} FINAL
    PREWHERE
      (
        (from IN (?1) AND NOT to IN (?1)) OR
        (NOT from IN (?1) AND to IN (?1))
      ) AND
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3) AND
      type = 'call'
    ORDER BY value DESC
    LIMIT ?4
    """

    args = [
      wallets,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      limit
    ]

    {query, args}
  end

  defp eth_spent_query(wallets, from, to) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    prewhere_clause =
      wallets
      |> Enum.map(fn list ->
        list = list |> Enum.map(fn x -> ~s/'#{x}'/ end) |> Enum.join(", ")
        "(from IN (#{list}) AND NOT to IN (#{list}))"
      end)
      |> Enum.join(" OR ")

    query = """
    SELECT from, SUM(value)
    FROM (
      SELECT any(value) as value, from
      FROM #{@table}
      PREWHERE (#{prewhere_clause})
      AND dt >= toDateTime(?1)
      AND dt <= toDateTime(?2)
      AND type == 'call'
      GROUP BY from, type, to, dt, transactionHash
    )
    GROUP BY from
    """

    args = [
      from_unix,
      to_unix
    ]

    {query, args}
  end

  defp eth_spent_over_time_query(wallets, from, to, interval) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    interval = DateTimeUtils.str_to_sec(interval)
    span = div(to_unix - from_unix, interval) |> max(1)

    query = """
    SELECT SUM(value), time
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
          toFloat64(0) AS value
        FROM numbers(?2)

        UNION ALL

        SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, sum(value) as value
          FROM (
            SELECT any(value) as value, dt
            FROM #{@table}
            PREWHERE from IN (?3) AND NOT to IN (?3)
            AND dt >= toDateTime(?4)
            AND dt <= toDateTime(?5)
            AND type == 'call'
            GROUP BY from, type, to, dt, transactionHash
          )
        GROUP BY time
      )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      span,
      wallets,
      from_unix,
      to_unix
    ]

    {query, args}
  end

  defp eth_top_transactions_query(from, to, limit) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    # only > 10K ETH transfers if range is > 1 week, otherwise only bigger than 1K
    value_filter = if Timex.diff(to, from, :days) < 7, do: 10_000, else: 1_000

    query = """
    SELECT
      toUnixTimestamp(dt), from, to, transactionHash, value
    FROM #{@table} FINAL
    PREWHERE
      value > ?1 AND
      type = 'call' AND
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    ORDER BY value DESC
    LIMIT ?4
    """

    args = [
      value_filter,
      from_unix,
      to_unix,
      limit
    ]

    {query, args}
  end
end
