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

  @type exchange_volume :: %{
          datetime: non_neg_integer(),
          exchange_inflow: float,
          exchange_outflow: float
        }

  use Ecto.Schema

  require Logger
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils

  @table "eth_transfers"
  @eth_decimals 1_000_000_000_000_000_000

  @primary_key false
  @timestamps_opts updated_at: false
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

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth transfers"
  end

  @doc ~s"""
  Return the `limit` biggest transfers for a list of wallets and time period.
  Only transfers which `from` address is in the list and `to` address is
  not in the list are selected.
  """
  @spec top_wallet_transfers(wallets, %DateTime{}, %DateTime{}, integer, String.t()) ::
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def top_wallet_transfers(wallets, from_datetime, to_datetime, limit, type) do
    wallet_transfers(wallets, from_datetime, to_datetime, limit, type)
  end

  @doc ~s"""
  The total ETH spent in the `from_datetime` - `to_datetime` interval
  """
  @spec eth_spent(wallets, %DateTime{}, %DateTime{}) ::
          {:ok, []} | {:ok, [{String.t(), float()}]} | {:error, String.t()}
  def eth_spent([], _, _), do: {:ok, []}

  def eth_spent(wallets, from_datetime, to_datetime) do
    {query, args} = eth_spent_query(wallets, from_datetime, to_datetime)

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
  time period [`from_datetime`, `to_datetime`]
  """
  @spec eth_spent_over_time(%Project{} | wallets, %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, list(spent_over_time_type)} | {:error, String.t()}
  def eth_spent_over_time(%Project{} = project, from_datetime, to_datetime, interval) do
    with {:ok, eth_addresses} <- Project.eth_addresses(project) do
      eth_spent_over_time(eth_addresses, from_datetime, to_datetime, interval)
    else
      {:error, error} ->
        Logger.warn(
          "Cannot get ETH addresses for project with id #{project.id}. Reason: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  def eth_spent_over_time([], _, _, _), do: {:ok, []}

  def eth_spent_over_time(wallets, from_datetime, to_datetime, interval) when is_list(wallets) do
    {query, args} = eth_spent_over_time_query(wallets, from_datetime, to_datetime, interval)

    ClickhouseRepo.query_transform(query, args, fn [value, datetime_str] ->
      %{
        datetime: datetime_str |> DateTimeUtils.from_erl!(),
        eth_spent: value / @eth_decimals
      }
    end)
  end

  @doc ~s"""
  Combines a list of lists of ethereum spent data for many projects to a list of ethereum spent data.
  The entries at the same positions in each list are summed.
  """
  @spec combine_eth_spent_by_all_projects(list({:ok, spent_over_time_type})) ::
          {:ok, list(spent_over_time_type)}
  def combine_eth_spent_by_all_projects(eth_spent_over_time_list) do
    total_eth_spent_over_time =
      eth_spent_over_time_list
      |> Enum.reject(fn
        {:ok, elem} when elem != [] and elem != nil -> false
        _ -> true
      end)
      |> Enum.map(fn {:ok, data} -> data end)
      |> Stream.zip()
      |> Stream.map(&Tuple.to_list/1)
      |> Enum.map(&reduce_eth_spent/1)

    {:ok, total_eth_spent_over_time}
  end

  @doc ~s"""
  Returns the inflow and outflow volume for a list of exchange_addresses between two datetimes
  """
  @spec exchange_volume(
          list(String.t()),
          %DateTime{},
          %DateTime{}
        ) :: {:ok, list(exchange_volume)} | {:error, String.t()}
  def exchange_volume(exchange_addresses, from_datetime, to_datetime) do
    exchange_addresses = exchange_addresses |> Enum.map(&String.downcase/1)
    {query, args} = exchange_volume_query(exchange_addresses, from_datetime, to_datetime)

    query
    |> ClickhouseRepo.query_transform(args, fn [dt, inflow, outflow] ->
      %{
        datetime: DateTime.from_unix!(dt),
        exchange_inflow: inflow,
        exchange_outflow: outflow
      }
    end)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  # Private functions

  defp wallet_transfers([], _, _, _, _), do: []

  defp wallet_transfers(wallets, from_datetime, to_datetime, limit, type) do
    {query, args} = wallet_transactions_query(wallets, from_datetime, to_datetime, limit, type)

    ClickhouseRepo.query_transform(query, args)
  end

  defp wallet_transactions_query(wallets, from_datetime, to_datetime, limit, :out) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)

    query = """
    SELECT from, type, to, dt, transactionHash, any(value) / #{@eth_decimals} as value
    FROM #{@table}
    PREWHERE from IN (?1) AND NOT to IN (?1)
    AND dt >= toDateTime(?2)
    AND dt <= toDateTime(?3)
    AND type == 'call'
    GROUP BY from, type, to, dt, transactionHash
    ORDER BY value DESC
    LIMIT ?4
    """

    args = [
      wallets,
      from_datetime_unix,
      to_datetime_unix,
      limit
    ]

    {query, args}
  end

  defp wallet_transactions_query(wallets, from_datetime, to_datetime, limit, :in) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)

    query = """
    SELECT from, type, to, dt, transactionHash, any(value) / #{@eth_decimals} as value
    FROM #{@table}
    PREWHERE NOT from IN (?1) AND to IN (?1)
    AND dt >= toDateTime(?2)
    AND dt <= toDateTime(?3)
    AND type == 'call'
    GROUP BY from, type, to, dt, transactionHash
    ORDER BY value desc
    LIMIT ?4
    """

    args = [
      wallets,
      from_datetime_unix,
      to_datetime_unix,
      limit
    ]

    {query, args}
  end

  defp wallet_transactions_query(wallets, from_datetime, to_datetime, limit, :all) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)

    query = """
    SELECT from, type, to, dt, transactionHash, any(value) / #{@eth_decimals} as value
    FROM #{@table}
    PREWHERE (
      (from IN (?1) AND NOT to IN (?1)) OR
      (NOT from IN (?1) AND to IN (?1)))
    AND dt >= toDateTime(?2)
    AND dt <= toDateTime(?3)
    AND type == 'call'
    GROUP BY from, type, to, dt, transactionHash
    ORDER BY value desc
    LIMIT ?4
    """

    args = [
      wallets,
      from_datetime_unix,
      to_datetime_unix,
      limit
    ]

    {query, args}
  end

  defp eth_spent_query(wallets, from_datetime, to_datetime) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)

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
      from_datetime_unix,
      to_datetime_unix
    ]

    {query, args}
  end

  defp eth_spent_over_time_query(wallets, from_datetime, to_datetime, interval) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    interval = DateTimeUtils.compound_duration_to_seconds(interval)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

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
      from_datetime_unix,
      to_datetime_unix
    ]

    {query, args}
  end

  defp exchange_volume_query(exchange_addresses, from_datetime, to_datetime) do
    query = """
    SELECT
      toUnixTimestamp(dt) as datetime,
     (inflow * price_usd) as exchange_inflow,
     (outflow * price_usd) as exchange_outflow
    FROM
    (
     SELECT dt, inflow, outflow
      FROM
      (
      SELECT
    	  toStartOfDay(dt) as dt,
    	  sum(value) / #{@eth_decimals} as inflow
      FROM #{@table}
      PREWHERE
          to IN (?1) AND NOT from IN (?1)
          AND dt >= toDateTime(?2)
          AND dt <= toDateTime(?3)
      GROUP BY dt
     )
     ALL INNER JOIN
     (
      SELECT
    	  toStartOfDay(dt) as dt,
    	  sum(value) / #{@eth_decimals} as outflow
      FROM #{@table}
        PREWHERE
          from IN (?1) AND NOT to IN (?1)
          AND dt >= toDateTime(?2)
          AND dt <= toDateTime(?3)
      GROUP BY dt
     ) USING dt
    )
    ALL INNER JOIN
    (
     SELECT
      toStartOfDay(dt) as dt, AVG(price_usd) as "price_usd"
     FROM prices
      PREWHERE
        name = 'ETH_ethereum'
        AND dt >= toDateTime(?2)
        AND dt <= toDateTime(?3)
     GROUP BY dt
    ) USING dt
    ORDER BY dt
    """

    args = [
      exchange_addresses,
      from_datetime,
      to_datetime
    ]

    {query, args}
  end

  defp reduce_eth_spent([%{datetime: datetime} | _] = values) do
    total_eth_spent =
      values
      |> Enum.reduce(0, fn %{eth_spent: eth_spent}, acc ->
        eth_spent + acc
      end)

    %{datetime: datetime, eth_spent: total_eth_spent}
  end
end
