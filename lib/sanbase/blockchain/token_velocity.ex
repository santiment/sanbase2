defmodule Sanbase.Blockchain.TokenVelocity do
  @moduledoc ~s"""

  """

  @type velocity_map :: %{
          datetime: %DateTime{},
          token_velocity: float()
        }

  alias Sanbase.Blockchain.{TransactionVolume, TokenCirculation}

  @doc ~s"""
  Return the token velocity for a given contract and time restrictions.
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

  def calc_token_velocity(active_tokens, transaction_volume) do
    if active_tokens > 0 do
      transaction_volume / active_tokens
    else
      0.0
    end
  end
end
