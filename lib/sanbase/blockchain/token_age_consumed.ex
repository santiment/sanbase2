defmodule Sanbase.Blockchain.TokenAgeConsumed do
  @moduledoc ~s"""
  Token Age Consumed (also known as Days Destroyed) is calculated by taking the
  number of ethers/tokens in a transaction and multiplying it by the number of blocks
  it has been since those ether/tokens were last moved.
  """

  @type t :: %__MODULE__{
          timestamp: %DateTime{},
          contract_address: String.t(),
          token_age_consuemd: float()
        }

  @typedoc ~s"""
  Returned by the `token_age_consumed/5` and `token_age_consumed!/5` functions
  TODO: Once the `burn_rate` GQL query is deprecated in favour of `token_age_consumed`
  remove the `burn_rate` field
  """
  @type token_age_consumed_map :: %{
          datetime: %DateTime{},
          burn_rate: float(),
          token_age_consumed: float()
        }

  @typedoc ~s"""
  Returned by the `average_token_age_consumed_in_days/5` function.
  It is calculated by dividing the token age consumed by the transaction volume
  to get actual average age of the tokens/ether
  """
  @type token_age_consumed_in_days_map :: %{
          datetime: %DateTime{},
          token_age_in_days: float()
        }

  use Ecto.Schema

  import Ecto.Changeset
  alias Sanbase.Timescaledb

  @table Timescaledb.table_name("eth_burn_rate")

  @primary_key false
  schema @table do
    field(:timestamp, :naive_datetime, primary_key: true)
    field(:contract_address, :string, primary_key: true)
    field(:token_age_consumed, :float, source: :burn_rate)
  end

  @doc false
  def changeset(%__MODULE__{} = token_age_consumed, attrs \\ %{}) do
    token_age_consumed
    |> cast(attrs, [:timestamp, :contract_address, :token_age_consumed])
    |> validate_number(:token_age_consumed, greater_than_or_equal_to: 0.0)
    |> validate_length(:contract_address, min: 1)
  end

  @doc ~s"""
  Returns the token age consumed for a given contract and time period
  """
  @spec token_age_consumed(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: {:ok, list(token_age_consumed_map)} | {:error, String.t()}
  def token_age_consumed(contract, from, to, interval, token_decimals \\ 0) do
    args = [from, to, contract]

    """
    SELECT sum(burn_rate) AS value
    FROM #{@table}
    WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3
    """
    |> Timescaledb.bucket_by_interval(args, interval)
    |> Timescaledb.timescaledb_execute(fn [datetime, token_age_consumed] ->
      token_age_consumed = token_age_consumed / :math.pow(10, token_decimals)

      %{
        datetime: Timescaledb.timestamp_to_datetime(datetime),
        burn_rate: token_age_consumed,
        token_age_consumed: token_age_consumed
      }
    end)
  end

  @doc ~s"""
  Returns the token age consumed for a given contract and time period
  """
  @spec token_age_consumed!(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: list(token_age_consumed_map) | no_return
  def token_age_consumed!(contract, from, to, interval, token_decimals \\ 0) do
    case token_age_consumed(contract, from, to, interval, token_decimals) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
  Returns the average token age in days of the transferred tokens/ether for a given
  contract and time period.
  To get the data for Ethereum pass "ETH" as contract
  """
  @spec token_age_consumed(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: {:ok, list(token_age_consumed_map)} | {:error, String.t()}
  def average_token_age_consumed_in_days(contract, from, to, interval, token_decimals \\ 0) do
    with {:ok, token_age_consumed} <-
           token_age_consumed(contract, from, to, interval, token_decimals),
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
        |> Enum.map(fn {%{token_age_consumed: token_age_consumed, datetime: datetime},
                        %{transaction_volume: trx_volume}} ->
          value = %{
            datetime: datetime,
            token_age_in_days: token_age_in_days(token_age_consumed, trx_volume)
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

  # `token_age_consumed` is calculated by multiplying by the number of blocks, not real timestamp
  # apply approximation that a block is produced on average each 15 seconds
  defp token_age_in_days(_, 0), do: 0

  defp token_age_in_days(token_age_consumed, trx_volume),
    do: token_age_consumed / trx_volume * 15 / 86400
end
