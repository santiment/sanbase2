defmodule Sanbase.Clickhouse.HistoricalBalance.Behaviour do
  @moduledoc ~s"""

  """

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @type address :: String.t()
  @type address_or_addresses :: address | list(address)
  @type decimals :: non_neg_integer()
  @type datetime :: DateTime.t()

  @type currency :: String.t()
  @type contract :: String.t()

  @type target :: contract | currency

  @type slug_balance_map :: %{
          slug: String.t(),
          balance: float()
        }

  @type historical_balance :: %{
          datetime: non_neg_integer(),
          balance: float()
        }

  @type balance_change ::
          {address, {balance_before :: number, balance_after :: number, balance_change :: number}}
          | {:error, String.t()}

  @doc ~s"""
  Return a list of all assets that the address holds or has held in the past and
  the latest balance.
  """
  @callback assets_held_by_address(address) ::
              {:ok, list(slug_balance_map)} | {:error, String.t()}

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
            ) ::
              {:ok, list(historical_balance)} | {:error, String.t()}

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
            ) ::
              {:ok, list(balance_change)} | {:error, String.t()}

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
            ) ::
              {:ok, list(balance_change)} | {:error, String.t()}

  @callback last_balance_before(
              address,
              target,
              decimals,
              before :: datetime
            ) :: {:ok, float()} | {:error, String.t()}

  @optional_callbacks historical_balance_change: 6
end
