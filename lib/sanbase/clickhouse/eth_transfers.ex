defmodule Sanbase.Clickhouse.EthTransfers do
  use Ecto.Schema

  import Ecto.Query
  import Sanbase.Clickhouse.EctoFunctions

  alias __MODULE__
  alias Sanbase.ClickhouseRepo

  @primary_key false
  @timestamps_opts updated_at: false
  schema "eth_transfers2" do
    field(:dt, :utc_datetime)
    field(:from, :string, primary_key: true)
    field(:to, :string, primary_key: true)
    field(:transactionHash, :string)
    field(:value, :float)
    field(:blockNumber, :integer)
    field(:transactionPosition, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth transfers"
  end

  @doc ~s"""
  Return the `size` biggest transfers for a given address and time period.
  """
  def top_address_transfers(from, from_datetime, to_datetime, size \\ 10) do
    query =
      from(
        transfer in EthTransfers,
        where:
          transfer.from == ^from and transfer.dt > ^from_datetime and transfer.dt < ^to_datetime,
        order_by: [desc: transfer.value],
        limit: ^size
      )
      |> query_all_use_prewhere()
  end

  @doc ~s"""
  Return the `size` biggest transfers for a list of wallets and time period.
  Only transfers which `from` address is in the list and `to` address is
  not in the list are selected.
  """
  def top_wallet_transfers(wallets, from_datetime, to_datetime, size, type) do
    wallet_transfers(wallets, from_datetime, to_datetime, size, type, desc: :value)
  end

  @doc ~s"""
  Return the `size` last transfers for a list of wallets and time period.
  Only transfers which `from` address is in the list and `to` address is
  not in the list are selected.
  """
  def last_wallet_transfers(wallets, from_datetime, to_datetime, size, type) do
    wallet_transfers(wallets, from_datetime, to_datetime, size, type, desc: :dt)
    |> Enum.reverse()
  end

  def eth_spent(wallets, from_datetime, to_datetime) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from in ^wallets and transfer.to not in ^wallets and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      select: sum(transfer.value)
    )
    |> ClickhouseRepo.one()
  end

  @doc ~s"""
  Return a list of maps `%{datetime: datetime, eth_spent: ethspent}` that shows
  how much ETH has been spent for the list of `wallets` for each `interval` in the
  time period [`from_datetime`, `to_datetime`]
  """
  @spec eth_spent_over_time(list(String.t()), %DateTime{}, %DateTime{}, Integer.t()) ::
          list(map())
  def eth_spent_over_time(wallets, from_datetime, to_datetime, interval) do
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
                eth_spent: value
              }
            end
          )

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  # Private functions

  defp wallet_transfers([], _, _, _, _, _), do: []

  defp wallet_transfers(wallets, from_datetime, to_datetime, size, :out, order_by)
       when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from in ^wallets and transfer.to not in ^wallets and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      order_by: ^order_by,
      limit: ^size
    )
    |> query_all_use_prewhere()
  end

  defp wallet_transfers(wallets, from_datetime, to_datetime, size, :in, order_by)
       when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from not in ^wallets and transfer.to in ^wallets and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      order_by: ^order_by,
      limit: ^size
    )
    |> query_all_use_prewhere()
  end

  defp wallet_transfers(wallets, from_datetime, to_datetime, size, :all, order_by)
       when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.dt > ^from_datetime and transfer.dt < ^to_datetime and
          ((transfer.from in ^wallets and transfer.to not in ^wallets) or
             (transfer.from not in ^wallets and transfer.to in ^wallets)),
      order_by: ^order_by,
      limit: ^size
    )
    |> query_all_use_prewhere()
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
      FROM eth_transfers2
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
end
