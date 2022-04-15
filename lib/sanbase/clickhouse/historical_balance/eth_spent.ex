defmodule Sanbase.Clickhouse.HistoricalBalance.EthSpent do
  @moduledoc ~s"""
  Module providing functions for fetching ethereum spent
  """

  alias Sanbase.Clickhouse.HistoricalBalance

  @type slug :: String.t()

  @type address :: String.t() | list(String.t())

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @type eth_spent_over_time :: %{
          datetime: DateTime.t(),
          eth_spent: number()
        }

  @type eth_spent_over_time_result :: {:ok, list(eth_spent_over_time)} | {:error, String.t()}

  @doc ~s"""
  For a given address or list of addresses returns the ethereum balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change.

  This is special case of balance_change/4 but as ethereum is used a lot for calculating
  ethereum spent this case avoids a call to the database to obtain the contract
  """
  @spec eth_balance_change(address, from :: DateTime.t(), to :: DateTime.t()) ::
          HistoricalBalance.Behaviour.balance_change_result()
  def eth_balance_change(addresses, from, to) do
    Sanbase.Balance.balance_change(addresses, "ethereum", from, to)
  end

  @doc ~s"""
  For a given address or list of addresses returns the ethereum  balance change for each bucket
  of size `interval` in the from-to time period
  """
  @spec eth_balance_change(address, from :: DateTime.t(), to :: DateTime.t(), interval) ::
          HistoricalBalance.Behaviour.historical_balance_change_result()
  def eth_balance_change(addresses, from, to, interval) do
    Sanbase.Balance.historical_balance_changes(addresses, "ethereum", from, to, interval)
  end

  @doc ~s"""
  For a given address or list of addresses calculate the ethereum spent.
  Ethereum spent is defined as follows:
    - If the combined balance of the addresses at `from` datetime is bigger than
    the combined balance at `to` datetime, the eth spent is the absolute value
    of the difference between the two balance
    - Zero otherwise
  """
  # @spec eth_spent(address | list(address), DateTime.t(), DateTime.t()) ::
  #         {:ok, number()} | {:error, String.t()} # TODO: Undo
  def eth_spent(addresses, from, to) do
    case eth_balance_change(addresses, from, to) do
      {:ok, balance_changes} ->
        eth_spent =
          balance_changes
          |> Enum.map(fn %{balance_change_amount: change} -> change end)
          |> Enum.sum()
          |> case do
            change when change < 0 -> abs(change)
            _ -> 0
          end

        {:ok, eth_spent}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  For a given address or list of addresses calculate the ethereum spent.
  Ethereum spent is defined as follows:
    - If the combined balance of the addresses decreases compared to the previous
    time bucket, the absolute value of the change is the ethereum spent
    - If the combined balance of the addresses increases compared to the previous
    time bucket, the ethereum spent is equal to 0
  """
  @spec eth_spent_over_time(address | list(address), DateTime.t(), DateTime.t(), interval) ::
          eth_spent_over_time_result()
  def eth_spent_over_time(addresses, from, to, interval)
      when is_binary(addresses) or is_list(addresses) do
    case eth_balance_change(addresses, from, to, interval) do
      {:ok, balance_changes} ->
        eth_spent_over_time =
          balance_changes
          |> Enum.map(fn
            %{balance_change_amount: change, datetime: dt} when change < 0 ->
              %{datetime: dt, eth_spent: abs(change)}

            %{datetime: dt} ->
              %{datetime: dt, eth_spent: 0}
          end)

        {:ok, eth_spent_over_time}

      {:error, error} ->
        {:error, error}
    end
  end
end
