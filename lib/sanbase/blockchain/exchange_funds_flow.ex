defmodule Sanbase.Blockchain.ExchangeFundsFlow do
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Timescaledb

  @table "eth_exchange_funds_flow"

  @primary_key false
  schema @table do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:incoming_exchange_funds, :float)
    field(:outgoing_exchange_funds, :float)
  end

  @doc false
  def changeset(%__MODULE__{} = exchange_funds_flow, attrs \\ %{}) do
    exchange_funds_flow
    |> cast(attrs, [
      :timestamp,
      :contract_address,
      :incoming_exchange_funds,
      :outgoing_exchange_funds
    ])
    |> validate_number(:outgoing_exchange_funds, greater_than_or_equal_to: 0.0)
    |> validate_number(:incoming_exchange_funds, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  def exchange_funds_flow(contract, from, to, interval) do
    args = [from, to, contract]

    """
    SELECT sum(incoming_exchange_funds) - sum(outgoing_exchange_funds) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> bucket_by_interval(args, interval)
    |> timescaledb_execute(fn [datetime, exchange_funds_flow] ->
      %{
        datetime: timestamp_to_datetime(datetime),
        exchange_funds_flow: exchange_funds_flow
      }
    end)
  end

  def exchange_funds_flow!(contract, from, to, interval) do
    case exchange_funds_flow(contract, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end
end
