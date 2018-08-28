defmodule Sanbase.Clickhouse.EthTransfers do
  use Ecto.Schema

  require Logger

  import Ecto.Query

  alias __MODULE__
  require Sanbase.ClickhouseRepo
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Model.Project

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
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth transfers"
  end

  @doc ~s"""
  Return the `size` biggest transfers for a given address and time period.
  """
  def top_address_transfers(from_address, from_datetime, to_datetime, size) do
    # The fragment should be `as value` and not `as trx_value` as the underlaying column name is `value`
    # `trx_value` comes from ecto schema
    from(
      transfer in EthTransfers,
      where:
        transfer.from_address == ^from_address and transfer.datetime > ^from_datetime and
          transfer.datetime < ^to_datetime,
      select: %{
        datetime: transfer.datetime,
        from_address: transfer.from_address,
        to_address: transfer.to_address,
        trx_hash: transfer.trx_hash,
        trx_value: fragment("divide(?,?) as value", transfer.trx_value, @eth_decimals)
      },
      order_by: [desc: transfer.trx_value],
      limit: ^size
    )
    |> ClickhouseRepo.all_prewhere()
  end

  @doc ~s"""
  Return the `size` biggest transfers for a list of wallets and time period.
  Only transfers which `from` address is in the list and `to` address is
  not in the list are selected.
  """
  def top_wallet_transfers(wallets, from_datetime, to_datetime, size, type) do
    wallet_transfers(wallets, from_datetime, to_datetime, size, type, desc: :trx_value)
  end

  @doc ~s"""
  Return the `size` last transfers for a list of wallets and time period.
  Only transfers which `from` address is in the list and `to` address is
  not in the list are selected.
  """
  def last_wallet_transfers(wallets, from_datetime, to_datetime, size, type) do
    {:ok, transfers} =
      wallet_transfers(wallets, from_datetime, to_datetime, size, type, desc: :datetime)

    {:ok, transfers |> Enum.reverse()}
  end

  def eth_spent(wallets, from_datetime, to_datetime) do
    eth_spent =
      from(
        transfer in EthTransfers,
        where:
          transfer.from_address in ^wallets and transfer.to_address not in ^wallets and
            transfer.datetime > ^from_datetime and transfer.datetime < ^to_datetime,
        select: sum(transfer.trx_value)
      )
      |> ClickhouseRepo.one()

    {:ok, eth_spent / @eth_decimals}
  end

  @doc ~s"""
  Return a list of maps `%{datetime: datetime, eth_spent: ethspent}` that shows
  how much ETH has been spent for the list of `wallets` for each `interval` in the
  time period [`from_datetime`, `to_datetime`]
  """
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

    ClickhouseRepo.query(query, args)
    |> case do
      {:ok, %{rows: rows}} ->
        result =
          Enum.map(
            rows,
            fn [value, datetime_str] ->
              %{
                datetime: datetime_str |> Sanbase.DateTimeUtils.from_erl!(),
                eth_spent: value / @eth_decimals
              }
            end
          )

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Returns the sum of the total ETH spent of all projects from the list projects
  """
  @spec eth_spent_by_projects(list(), %DateTime{}, %DateTime{}) ::
          {:ok, number()} | {:ok, nil} | {:error, String.t()}
  def eth_spent_by_projects([], _from_datetime, _to_datetime), do: {:ok, nil}

  def eth_spent_by_projects(projects, from_datetime, to_datetime) do
    total_eth_spent =
      projects
      |> Enum.map(&Task.async(fn -> eth_spent(&1, from_datetime, to_datetime) end))
      |> Stream.map(&Task.await(&1, 25_000))
      |> Stream.reject(fn {:ok, sum} -> sum == nil end)
      |> Enum.reduce(0, fn
        {:ok, sum}, acc ->
          acc + sum

        {:error, error}, acc ->
          Logger.warn("Error while calculating the total ETH spent by projects: #{error}")

          acc
      end)

    {:ok, total_eth_spent}
  end

  @doc ~s"""
  Returns the sum of 'out' transactions over the specified period of time for all projecs,
  grouped by the specified interval.
  """
  @spec eth_spent_over_time_by_projects(list(), %DateTime{}, %DateTime{}, String.t()) ::
          {:ok, list()} | {:error, String.t()}
  def eth_spent_over_time_by_projects([], _from_datetime, _to_datetime, _interval), do: {:ok, []}

  def eth_spent_over_time_by_projects(projects, from_datetime, to_datetime, interval) do
    {:ok, eth_addresses} = Project.eth_addresses(projects)

    total_eth_spent_over_time =
      eth_addresses
      |> Enum.map(
        &Task.async(fn ->
          eth_spent_over_time(&1, from_datetime, to_datetime, interval)
        end)
      )
      |> Stream.map(&Task.await(&1, 25_000))
      |> Stream.reject(fn
        {:error, _} -> true
        {:ok, []} -> true
        {:ok, _} -> false
      end)
      |> Enum.map(fn {:ok, data} -> data end)
      |> Stream.zip()
      |> Stream.map(&Tuple.to_list/1)
      |> Enum.map(&reduce_eth_spent/1)

    {:ok, total_eth_spent_over_time}
  end

  # Private functions

  defp wallet_transfers([], _, _, _, _, _), do: []

  defp wallet_transfers(wallets, from_datetime, to_datetime, size, :out, order_by)
       when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from_address in ^wallets and transfer.to_address not in ^wallets and
          transfer.datetime > ^from_datetime and transfer.datetime < ^to_datetime,
      order_by: ^order_by,
      limit: ^size
    )
    |> ClickhouseRepo.all_prewhere()
    |> divide_by_eth_decimals()
  end

  defp wallet_transfers(wallets, from_datetime, to_datetime, size, :in, order_by)
       when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from_address not in ^wallets and transfer.to_address in ^wallets and
          transfer.datetime > ^from_datetime and transfer.datetime < ^to_datetime,
      order_by: ^order_by,
      limit: ^size
    )
    |> ClickhouseRepo.all_prewhere()
    |> divide_by_eth_decimals()
  end

  defp wallet_transfers(wallets, from_datetime, to_datetime, size, :all, order_by)
       when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.datetime > ^from_datetime and transfer.datetime < ^to_datetime and
          ((transfer.from_address in ^wallets and transfer.to_address not in ^wallets) or
             (transfer.from_address not in ^wallets and transfer.to_address in ^wallets)),
      order_by: ^order_by,
      limit: ^size
    )
    |> ClickhouseRepo.all_prewhere()
    |> divide_by_eth_decimals()
  end

  defp eth_spent_over_time_query(wallets, from_datetime, to_datetime, interval) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    span = div(to_datetime_unix - from_datetime_unix, interval)

    query = """
    SELECT SUM(value), time
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
        toFloat64(0) AS value
      FROM numbers(?2)

      UNION ALL

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, sum(value) as value
      FROM #{@table}
      PREWHERE from IN (?3) AND NOT to IN (?3)
      AND dt >= toDateTime(?4)
      AND dt <= toDateTime(?5)
      GROUP BY time
      ORDER BY time
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

  defp reduce_eth_spent([%{datetime: datetime} | _] = values) do
    total_eth_spent =
      values
      |> Enum.reduce(0, fn %{eth_spent: eth_spent}, acc ->
        eth_spent + acc
      end)

    %{datetime: datetime, eth_spent: total_eth_spent}
  end

  defp divide_by_eth_decimals({:ok, transfers} = tuple) do
    transfers =
      transfers
      |> Enum.map(fn %EthTransfers{trx_value: trx_value} = eth_transfer ->
        %EthTransfers{eth_transfer | trx_value: trx_value / @eth_decimals}
      end)

    {:ok, transfers}
  end

  defp divide_by_eth_decimals(data), do: data
end
