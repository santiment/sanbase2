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
  Return the `size` biggest transfers for a given wallet or list of wallets and time period.
  If a list of wallet is provided, then only transfers which `from` address is in the
  list and `to` address is not in the list are selected.
  """
  def top_wallet_transfers([], _, _, _, _), do: []

  def top_wallet_transfers(wallets, from_datetime, to_datetime, size, :out)
      when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from in ^wallets and transfer.to not in ^wallets and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      order_by: [desc: transfer.value],
      limit: ^size
    )
    |> query_all_use_prewhere()
  end

  def top_wallet_transfers(wallets, from_datetime, to_datetime, size, :in)
      when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from not in ^wallets and transfer.to in ^wallets and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      order_by: [desc: transfer.value],
      limit: ^size
    )
    |> query_all_use_prewhere()
  end

  def top_wallet_transfers(wallets, from_datetime, to_datetime, size, :all)
      when is_list(wallets) do
    from(
      transfer in EthTransfers,
      where:
        transfer.dt > ^from_datetime and transfer.dt < ^to_datetime and
          ((transfer.from in ^wallets and transfer.to not in ^wallets) or
             (transfer.from not in ^wallets and transfer.to in ^wallets)),
      order_by: [desc: transfer.value],
      limit: ^size
    )
    |> query_all_use_prewhere()
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

  # TODO: The group by specific to Clickhouse could be extracted as a macros that hide the implementation
  def eth_spent_over_time(wallets, from_datetime, to_datetime, interval) do
    from(
      transfer in EthTransfers,
      where:
        transfer.from in ^wallets and transfer.to not in ^wallets and transfer.dt > ^from_datetime and
          transfer.dt < ^to_datetime,
      group_by: fragment("time"),
      order_by: fragment("time"),
      select: %{
        datetime:
          fragment(
            "intDiv(toUInt32(?), ?) * ? as time",
            transfer.dt,
            ^interval,
            ^interval
          ),
        eth_spent: sum(transfer.value)
      }
    )
    |> ClickhouseRepo.all()
  end

  def eth_spent_over_time2(wallets, from_datetime, to_datetime, interval) do
    numbers = 30
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)
    span = div(to_datetime_unix - from_datetime_unix, interval) + 1

    query = """
    SELECT SUM(value), time
    FROM (
      SELECT
        toUInt32((#{from_datetime_unix} + number * #{interval})) as time,
        toFloat64(0) AS value
      FROM numbers(#{span})

      UNION ALL

      SELECT intDiv(toUInt32(e0."dt"), ?1) * ?2 as time,
      sum(e0."value") as value FROM "eth_transfers2" AS e0
      WHERE ((((e0."from" IN (?3)) AND NOT (e0."to" IN (?4))) AND (e0."dt" > ?5)) AND (e0."dt" < ?6))
      GROUP BY time
      ORDER BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      interval,
      wallets,
      wallets,
      from_datetime_unix,
      to_datetime_unix
    ]

    Ecto.Adapters.SQL.query(
      ClickhouseRepo,
      query,
      args
    )
    |> IO.inspect(limit: :infinity)

    :ok
  end
end
