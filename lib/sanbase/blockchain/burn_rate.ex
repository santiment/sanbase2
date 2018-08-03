defmodule Sanbase.Blockchain.BurnRate do
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Timescaledb

  @table "eth_burn_rate"

  @primary_key false
  schema @table do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:burn_rate, :float)
  end

  @doc false
  def changeset(%__MODULE__{} = burn_rate, attrs \\ %{}) do
    burn_rate
    |> cast(attrs, [:timestamp, :contract_address, :burn_rate])
    |> validate_number(:burn_rate, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  def burn_rate(contract, from, to, interval, token_decimals \\ 0) do
    args = [from, to, contract]

    """
    SELECT sum(burn_rate) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> bucket_by_interval(args, interval)
    |> timescaledb_execute(fn [datetime, burn_rate] ->
      %{
        datetime: timestamp_to_datetime(datetime),
        burn_rate: burn_rate / :math.pow(10, token_decimals)
      }
    end)
  end

  def burn_rate!(contract, from, to, interval, token_decimals \\ 0) do
    case burn_rate(contract, from, to, interval) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def first_datetime(contract) do
    timescale_first_datetime(
      "FROM #{@table} WHERE contract_address = $1",
      [contract]
    )
  end
end
