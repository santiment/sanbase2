defmodule Sanbase.Clickhouse.HistoricalBalance.Behaviour do
  @moduledoc ~s"""
  Behavior for defining the callback functions for a module implemening
  historical balances for a given blockchain.

  In order to add a new blockchain the following steps must be done:
  - Implement the behaviour
  - Add dispatch logic in the `HistoricalBalance` dispatch module.
  """

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @type slug :: String.t()
  @type address :: String.t()
  @type address_or_addresses :: address | list(address)
  @type decimals :: non_neg_integer()
  @type datetime :: DateTime.t()

  @type contract :: String.t()
  @type xrp_target :: %{currency: String.t(), issuer: String.t()}
  @type target :: contract | xrp_target

  @type slug_balance_map :: %{
          slug: slug,
          balance: float()
        }

  @type address_balance_map :: %{
          address: address,
          balance: float()
        }

  @type historical_balance :: %{
          datetime: datetime(),
          balance: float()
        }

  @type historical_balance_result :: {:ok, list(historical_balance)} | {:error, String.t()}

  @type balance_change :: %{
          address: address,
          balance_start: number,
          balance_end: number,
          balance_change_amount: number,
          balance_change_percent: number
        }

  @type balance_change_result :: {:ok, list(balance_change)} | {:error, String.t()}

  @type historical_balance_change :: %{
          datetime: datetime(),
          balance_change: number()
        }

  @type historical_balance_change_result ::
          {:ok, list(historical_balance_change)} | {:error, String.t()}

  @doc ~s"""
  Return a list of all assets that the address holds or has held in the past and
  the latest balance.
  """
  @callback assets_held_by_address(address) ::
              {:ok, list(slug_balance_map)} | {:error, String.t()}

  @doc ~s"""
  Return a list of all assets that the address holds or has held in the past and
  the latest balance.
  """
  @callback current_balance(address, target, decimals) ::
              {:ok, list(address_balance_map)} | {:error, String.t()}

  @doc ~s"""
  For a given address or list of addresses returns the combined
  balance for each bucket of size `interval` in the from-to time period
  """
  @callback historical_balance(
              address_or_addresses,
              target,
              decimals,
              from :: datetime,
              to :: datetime,
              interval
            ) :: historical_balance_result()

  @doc ~s"""
  For a given address or list of addresses returns the balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change
  """
  @callback balance_change(
              address_or_addresses,
              target,
              decimals,
              from :: datetime,
              to :: datetime
            ) :: balance_change_result()

  @doc ~s"""
  For a given address or list of addresses returns the balance change for each bucket
  of size `interval` in the from-to time period.
  """
  @callback historical_balance_change(
              address_or_addresses,
              target,
              decimals,
              from :: datetime,
              to :: datetime,
              interval
            ) :: historical_balance_change_result()

  @callback last_balance(
              list(address),
              target,
              decimals,
              from :: datetime,
              to :: datetime
            ) :: {:ok, float()} | {:error, String.t()}

  @callback last_balance_before(
              address,
              target,
              decimals,
              before :: datetime
            ) :: {:ok, float()} | {:error, String.t()}

  @optional_callbacks historical_balance_change: 6, last_balance: 5
end
