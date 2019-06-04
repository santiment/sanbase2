defmodule Sanbase.Blockchain.TokenVelocity do
  @moduledoc ~s"""
  Token Velocity is a metric which estimates the average frequency
  at which the tokens change hands during some period of time.

  Example:
  * Alice gives Bob 10 tokens at block 1 and
  * Bob gives Charlie 10 tokens at block 2

  The total transaction volume which is generated for block 1 and 2 is `10 + 10 = 20`
  The tokens being in circulation is actually `10` - because the same 10 tokens have been transacted.
  Token Velocity for blocks 1 and 2 is `20 / 10 = 2`
  """

  @type velocity_map :: %{
          datetime: %DateTime{},
          token_velocity: float()
        }

  alias Sanbase.Blockchain.{TransactionVolume, TokenCirculation}
  alias Sanbase.Timescaledb

  @token_circulation_table Timescaledb.table_name("eth_coin_circulation")

  @doc ~s"""
  Return the token velocity for a given contract and time restrictions.
  Token velocity for a given interval is calculatied by taking the `SUM` of the transaction volume
  for this interval and the `SUM` of the token circulation for :less_than_a_day (number of active tokens each day)
  for this interval and divide them.
  """
  @spec token_velocity(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: {:ok, list(velocity_map)} | {:error, String.t()}
  def token_velocity(contract, from, to, interval, token_decimals \\ 0) do
    with {:ok, transaction_volume} <-
           TransactionVolume.transaction_volume(
             contract,
             from,
             to,
             interval,
             token_decimals
           ),
         {:ok, token_circulation} <-
           TokenCirculation.token_circulation(
             :less_than_a_day,
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      token_velocity =
        Enum.zip(transaction_volume, token_circulation)
        |> Enum.map(fn {
                         %{transaction_volume: transaction_volume, datetime: datetime},
                         %{token_circulation: active_tokens}
                       } ->
          %{
            datetime: datetime,
            token_velocity: calc_token_velocity(active_tokens, transaction_volume)
          }
        end)

      {:ok, token_velocity}
    else
      {:error, error} -> {:error, error}
      error -> {:error, inspect(error)}
    end
  end

  @doc ~s"""
  Return the token velocity for a given contract and time restrictions.
  """
  @spec token_velocity!(
          String.t(),
          %DateTime{},
          %DateTime{},
          String.t(),
          non_neg_integer()
        ) :: list(velocity_map) | no_return
  def token_velocity!(contract, from, to, interval, token_decimals \\ 0) do
    case token_velocity(contract, from, to, interval, token_decimals) do
      {:ok, result} -> result
      {:error, error} -> raise(error)
    end
  end

  @doc ~s"""
  Used from Utils.calibrate_interval when metric is called without interval to build one.
  Take the first datetime for contract from token_circulation_table since token velocity does not have own table.
  """
  def first_datetime(contract) do
    "FROM #{@token_circulation_table} WHERE contract_address = $1"
    |> Timescaledb.first_datetime([contract])
  end

  # Private functions

  defp calc_token_velocity(active_tokens, transaction_volume) do
    if active_tokens > 0 do
      Float.round(transaction_volume / active_tokens, 2)
    else
      0.0
    end
  end
end
