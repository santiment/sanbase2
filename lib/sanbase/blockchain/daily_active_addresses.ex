defmodule Sanbase.Blockchain.DailyActiveAddresses do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Timescaledb

  @table Timescaledb.table_name("eth_daily_active_addresses")

  @primary_key false
  schema @table do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:active_addresses, :integer)
  end

  @doc false
  def changeset(%__MODULE__{} = active_addresses, attrs \\ %{}) do
    active_addresses
    |> cast(attrs, [:timestamp, :contract_address, :active_addresses])
    |> validate_number(:active_addresses, greater_than_or_equal_to: 0)
    |> validate_length(:contract_address, min: 1)
  end

  def average_active_addresses(contracts, from, to) do
    contracts = List.wrap(contracts)
    args = [from, to, contracts]

    query = """
    SELECT contract_address, coalesce(avg(active_addresses), 0) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = ANY($3)
    GROUP BY contract_address
    """

    {:ok, result} =
      {query, args}
      |> Timescaledb.timescaledb_execute(fn [contract, avg_active_addresses] ->
        avg_active_addresses =
          avg_active_addresses
          |> Decimal.round()
          |> Decimal.to_integer()

        {contract, avg_active_addresses}
      end)

    {:ok, result}
  end

  def average_active_addresses(contract, from, to, interval) do
    args = [from, to, contract]

    """
    SELECT avg(active_addresses) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> Timescaledb.bucket_by_interval(args, interval)
    |> Timescaledb.timescaledb_execute(fn [datetime, active_addresses] ->
      %{
        datetime: datetime |> Timescaledb.timestamp_to_datetime(),
        active_addresses:
          active_addresses
          |> Decimal.round()
          |> Decimal.to_integer()
      }
    end)
  end

  def average_active_addresses!(contract, from, to, interval) do
    case average_active_addresses(contract, from, to, interval) do
      {:ok, result} -> result
      # TODO: This error can never match
      {:error, error} -> raise(error)
    end
  end

  def first_datetime(contract) do
    "FROM #{@table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end
end
