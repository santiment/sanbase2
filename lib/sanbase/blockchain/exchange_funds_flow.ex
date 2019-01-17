defmodule Sanbase.Blockchain.ExchangeFundsFlow do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Timescaledb

  @table Timescaledb.table_name("eth_exchange_funds_flow")

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

  def transactions_in(contracts, from, to) do
    args = [from, to, contracts]

    query = """
    SELECT contract_address, coalesce(sum(incoming_exchange_funds),0) as value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = ANY($3)
    GROUP BY contract_address
    """

    {query, args}
    |> Timescaledb.timescaledb_execute(fn [contract, inflow] ->
      %{
        contract: contract,
        inflow: inflow
      }
    end)
  end

  def transactions_in_over_time(contract, from, to, interval, token_decimals \\ 0) do
    args = [from, to, contract]

    """
    SELECT (coalesce(sum(incoming_exchange_funds),0)) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> Timescaledb.bucket_by_interval(args, interval)
    |> Timescaledb.timescaledb_execute(fn [datetime, inflow] ->
      %{
        datetime: Timescaledb.timestamp_to_datetime(datetime),
        inflow: inflow / :math.pow(10, token_decimals)
      }
    end)
  end

  def transactions_in_out_difference(contract, from, to, interval, token_decimals \\ 0) do
    args = [from, to, contract]

    """
    SELECT (coalesce(sum(incoming_exchange_funds),0)-coalesce(sum(outgoing_exchange_funds),0)) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> Timescaledb.bucket_by_interval(args, interval)
    |> Timescaledb.timescaledb_execute(fn [datetime, in_out_difference] ->
      %{
        datetime: Timescaledb.timestamp_to_datetime(datetime),
        in_out_difference: in_out_difference / :math.pow(10, token_decimals)
      }
    end)
  end

  def transactions_in_out_difference!(contract, from, to, interval, token_decimals \\ 0) do
    case transactions_in_out_difference(contract, from, to, interval, token_decimals) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def first_datetime(contract) do
    "FROM #{@table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end
end
