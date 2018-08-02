defmodule Sanbase.Blockchain.TransactionVolume do
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Timescaledb

  @table "eth_transaction_volume"

  @primary_key false
  schema @table do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:transaction_volume, :float)
  end

  @doc false
  def changeset(%__MODULE__{} = transaction_volume, attrs \\ %{}) do
    transaction_volume
    |> cast(attrs, [:timestamp, :contract_address, :transaction_volume])
    |> validate_number(:transaction_volume, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  def transaction_volume(contract, from, to, interval) do
    args = [from, to, contract]

    """
    SELECT sum(transaction_volume) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> bucket_by_interval(args, interval)
    |> timescaledb_execute(fn [datetime, transaction_volume] ->
      %{
        datetime: timestamp_to_datetime(datetime),
        transaction_volume: transaction_volume
      }
    end)
  end

  def transaction_volume!(contract, from, to, interval) do
    case transaction_volume(contract, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end
end
