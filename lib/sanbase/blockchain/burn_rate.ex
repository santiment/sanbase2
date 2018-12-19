defmodule Sanbase.Blockchain.BurnRate do
  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Timescaledb

  @table Timescaledb.table_name("eth_burn_rate")

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
    |> Timescaledb.bucket_by_interval(args, interval)
    |> Timescaledb.timescaledb_execute(fn [datetime, burn_rate] ->
      %{
        datetime: Timescaledb.timestamp_to_datetime(datetime),
        burn_rate: burn_rate / :math.pow(10, token_decimals)
      }
    end)
  end

  def burn_rate!(contract, from, to, interval, token_decimals \\ 0) do
    case burn_rate(contract, from, to, interval, token_decimals) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  def average_token_age_consumed_in_days(contract, from, to, interval, token_decimals \\ 0) do
    with {:ok, token_age_consumed} <- burn_rate(contract, from, to, interval, token_decimals),
         {:ok, transaction_volume} <-
           Sanbase.Blockchain.TransactionVolume.transaction_volume(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      average_token_age_consumed_in_days =
        Enum.zip(token_age_consumed, transaction_volume)
        |> Enum.map(fn {%{burn_rate: burn_rate, datetime: datetime},
                        %{transaction_volume: trx_volume}} ->
          value = %{
            datetime: datetime,
            token_age_in_days: token_age_in_days(burn_rate, trx_volume)
          }
        end)

      {:ok, average_token_age_consumed_in_days}
    else
      {:error, error} -> {:error, error}
      error -> {:error, inspect(error)}
    end
  end

  def first_datetime(contract) do
    "FROM #{@table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end

  # Private functions

  # `burn_rate` is calculated by multiplying by the number of blocks, not real timestamp
  # apply approximation that a block is produced on average each 15 seconds
  defp token_age_in_days(_, 0), do: 0
  defp token_age_in_days(burn_rate, trx_volume), do: burn_rate / trx_volume * 15 / 86400
end
