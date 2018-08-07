defmodule Sanbase.Blockchain.DailyActiveAddresses do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Timescaledb

  @table "eth_daily_active_addresses"

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

  def active_addresses(contract, from, to) do
    args = [from, to, contract]

    query = """
    SELECT avg(active_addresses) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """

    {:ok, result} =
      {query, args}
      |> Timescaledb.timescaledb_execute(fn [active_addresses] ->
        case active_addresses do
          nil ->
            0

          %Decimal{} = d ->
            d
            |> Decimal.round()
            |> Decimal.to_integer()
        end
      end)

    {:ok, result |> List.first()}
  end

  def active_addresses(contract, from, to, interval) do
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

  def active_addresses!(contract, from, to, interval) do
    case active_addresses(contract, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def first_datetime(contract) do
    "FROM #{@table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end
end
