defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances and balance changes.
  This module dispatches to underlaying modules and serves as common interface
  for many different database tables and schemas.
  """

  use AsyncWith

  alias Sanbase.Model.Project

  @async_with_timeout 29_000

  alias Sanbase.Clickhouse.HistoricalBalance.{
    BchBalance,
    BnbBalance,
    BtcBalance,
    Erc20Balance,
    EthBalance,
    LtcBalance,
    XrpBalance
  }

  @infrastructure_to_module %{
    "BCH" => BchBalance,
    "BNB" => BnbBalance,
    "BEP2" => BnbBalance,
    "BTC" => BtcBalance,
    "LTC" => LtcBalance,
    "XRP" => XrpBalance,
    "ETH" => [EthBalance, Erc20Balance]
  }
  @supported_infrastructures Map.keys(@infrastructure_to_module)
  def supported_infrastructures(), do: @supported_infrastructures

  @type selector :: %{
          required(:infrastructure) => String.t(),
          optional(:currency) => String.t(),
          optional(:slug) => String.t()
        }

  @type slug :: String.t()

  @type address :: String.t() | list(String.t())

  @typedoc ~s"""
  An interval represented as string. It has the format of number followed by one of:
  ns, ms, s, m, h, d or w - each representing some time unit
  """
  @type interval :: String.t()

  @typedoc ~s"""
  The type returned by the historical_balance/5 function
  """
  @type historical_balance_return ::
          {:ok, []}
          | {:ok, list(%{datetime: DateTime.t(), balance: number()})}
          | {:error, String.t()}

  @doc ~s"""
  Return a list of the assets that a given address currently holds or
  has held in the past.

  This can be combined with the historical balance query to see the historical
  balance of all currently owned assets
  """
  @spec assets_held_by_address(map()) :: {:ok, list(map())} | {:error, String.t()}
  def assets_held_by_address(%{infrastructure: "ETH", address: address}) do
    async with {:ok, erc20_assets} <- Erc20Balance.assets_held_by_address(address),
               {:ok, ethereum} <- EthBalance.assets_held_by_address(address) do
      {:ok, ethereum ++ erc20_assets}
    end
  end

  def assets_held_by_address(%{infrastructure: infr, address: address}) do
    case Map.get(@infrastructure_to_module, infr) do
      nil -> {:error, "Infrastructure #{infr} is not supported."}
      module -> module.assets_held_by_address(address)
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the `slug` balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change
  """
  @spec balance_change(selector, address, from :: DateTime.t(), to :: DateTime.t()) ::
          __MODULE__.Behaviour.balance_change_result()
  def balance_change(selector, address, from, to) do
    selector = selector |> Map.put_new(:slug, nil)

    case selector_to_args(selector) do
      {module, asset, decimals} ->
        module.balance_Change(address, asset, decimals, from, to)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  For a given address or list of addresses returns the combined `slug` balance for each bucket
  of size `interval` in the from-to time period
  """
  @spec historical_balance(selector, address, from :: DateTime.t(), to :: DateTime.t(), interval) ::
          __MODULE__.Behaviour.historical_balance_result()
  def historical_balance(selector, address, from, to, interval) do
    case selector_to_args(selector) do
      {module, asset, decimals} ->
        module.historical_balance(address, asset, decimals, from, to, interval)

      {:error, error} ->
        {:error, error}
    end
  end

  # erc20 case
  defp selector_to_args(%{infrastructure: "ETH", slug: slug})
       when is_binary(slug) and slug != "ethereum" do
    with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug),
         do: {Erc20Balance, contract, decimals}
  end

  defp selector_to_args(%{infrastructure: "ETH"}) do
    with {:ok, contract, decimals} <- Project.contract_info_by_slug("ethereum"),
         do: {EthBalance, contract, decimals}
  end

  defp selector_to_args(%{infrastructure: "XRP"} = selector) do
    currency = Map.get(selector, :currency, "XRP")
    {XrpBalance, currency, 0}
  end

  defp selector_to_args(%{infrastructure: "BTC"}) do
    with {:ok, contract, decimals} <- Project.contract_info_by_slug("bitcoin"),
         do: {BtcBalance, contract, decimals}
  end

  defp selector_to_args(%{infrastructure: "BCH"}) do
    with {:ok, contract, decimals} <- Project.contract_info_by_slug("bitcoin-cash"),
         do: {BchBalance, contract, decimals}
  end

  defp selector_to_args(%{infrastructure: "LTC"}) do
    with {:ok, contract, decimals} <- Project.contract_info_by_slug("litecoin"),
         do: {LtcBalance, contract, decimals}
  end

  defp selector_to_args(%{infrastructure: "BNB"} = selector) do
    slug = Map.get(selector, :slug, "binance-coin")

    with {:ok, contract, decimals} <- Project.contract_info_by_slug(slug),
         do: {BnbBalance, contract, decimals}
  end
end
