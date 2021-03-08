defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances and balance changes.
  This module dispatches to underlaying modules and serves as common interface
  for many different database tables and schemas.
  """

  use AsyncWith

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.Model.Project

  alias Sanbase.Clickhouse.HistoricalBalance.{
    BchBalance,
    BnbBalance,
    BtcBalance,
    Erc20Balance,
    EthBalance,
    LtcBalance,
    XrpBalance
  }

  @async_with_timeout 29_000

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

  def assets_held_by_address(%{infrastructure: infr, address: address}) do
    case selector_to_args(%{infrastructure: infr}) do
      %{blockchain: blockchain} when blockchain in ["ethereum", "bitcoin"] ->
        Sanbase.Balance.assets_held_by_address(address)

      %{module: module} ->
        module.assets_held_by_address(address)

      {:error, error} ->
        {:error, error}
    end
    |> maybe_apply_function(fn data -> Enum.sort_by(data, &Map.get(&1, :balance), :desc) end)
  end

  @doc ~s"""
  For a given address or list of addresses returns the `slug` balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change
  """
  @spec balance_change(selector, address, from :: DateTime.t(), to :: DateTime.t()) ::
          __MODULE__.Behaviour.balance_change_result()

  def balance_change(selector, address, from, to) do
    case selector_to_args(selector) do
      %{blockchain: blockchain, slug: slug} when blockchain in ["ethereum", "bitcoin"] ->
        Sanbase.Balance.balance_change(address, slug, from, to)

      %{module: module, asset: asset, decimals: decimals} ->
        module.balance_change(address, asset, decimals, from, to)

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
      %{blockchain: blockchain, slug: slug} when blockchain in ["ethereum", "bitcoin"] ->
        Sanbase.Balance.historical_balance(address, slug, from, to, interval)

      %{module: module, asset: asset, decimals: decimals} ->
        module.historical_balance(address, asset, decimals, from, to, interval)

      {:error, error} ->
        {:error, error}
    end
  end

  @spec current_balance(selector, address | list(address)) ::
          __MODULE__.Behaviour.current_balance_result()
  def current_balance(selector, address) do
    case selector_to_args(selector) do
      %{blockchain: blockchain, slug: slug} when blockchain in ["ethereum", "bitcoin"] ->
        Sanbase.Balance.current_balance(address, slug)

      %{module: module, asset: asset, decimals: decimals} ->
        module.current_balance(address, asset, decimals)

      {:error, error} ->
        {:error, error}
    end
  end

  defguard is_ethereum(map)
           when (is_map_key(map, :slug) and map.slug == "ethereum") or
                  (is_map_key(map, :contract) and map.contract == "ETH") or
                  (is_map_key(map, :infrastructure) and not is_map_key(map, :slug) and
                     map.infrastructure == "ETH")

  @spec selector_to_args(selector) ::
          {module(), String.t(), non_neg_integer()} | {:error, tuple()}

  def selector_to_args(
        %{infrastructure: "ETH", contract: contract, decimals: decimals} = selector
      )
      when is_binary(contract) and is_number(decimals) and decimals > 0 and
             not is_ethereum(selector) do
    %{
      module: Erc20Balance,
      asset: String.downcase(contract),
      contract: String.downcase(contract),
      blockchain: Project.infrastructure_to_blockchain("ETH"),
      slug: nil,
      decimals: decimals
    }
  end

  def selector_to_args(%{} = selector) when is_ethereum(selector) do
    selector = Map.put_new(selector, :slug, "ethereum")

    with %{slug: slug, contract: contract, decimals: decimals, infrastructure: "ETH"} <-
           get_project_details(selector) do
      %{
        module: EthBalance,
        asset: contract,
        contract: contract,
        blockchain: Project.infrastructure_to_blockchain("ETH"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "ETH", slug: slug} = selector) when is_binary(slug) do
    with %{contract: contract, decimals: decimals} <- get_project_details(selector) do
      %{
        module: Erc20Balance,
        asset: contract,
        contract: contract,
        blockchain: Project.infrastructure_to_blockchain("ETH"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "XRP"} = selector) do
    %{
      module: XrpBalance,
      asset: Map.get(selector, :currency, "XRP"),
      currency: Map.get(selector, :currency, "XRP"),
      blockchain: Project.infrastructure_to_blockchain("XRP"),
      slug: "ripple",
      decimals: 0
    }
  end

  def selector_to_args(%{infrastructure: "BTC"} = selector) do
    selector = Map.put_new(selector, :slug, "bitcoin")

    with %{slug: slug, contract: contract, decimals: decimals} <- get_project_details(selector) do
      %{
        module: BtcBalance,
        asset: contract,
        contract: contract,
        blockchain: Project.infrastructure_to_blockchain("BTC"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "BCH"} = selector) do
    selector = Map.put_new(selector, :slug, "bitcoin-cash")

    with %{slug: slug, contract: contract, decimals: decimals} <- get_project_details(selector) do
      %{
        module: BchBalance,
        asset: contract,
        contract: contract,
        blockchain: Project.infrastructure_to_blockchain("BCH"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "LTC"} = selector) do
    selector = Map.put_new(selector, :slug, "litecoin")

    with %{slug: slug, contract: contract, decimals: decimals} <- get_project_details(selector) do
      %{
        module: LtcBalance,
        asset: contract,
        contract: contract,
        blockchain: Project.infrastructure_to_blockchain("LTC"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "BNB"} = selector) do
    selector = Map.put_new(selector, :slug, "binance-coin")

    with %{slug: slug, contract: contract, decimals: decimals} <- get_project_details(selector) do
      %{
        module: BnbBalance,
        asset: contract,
        contract: contract,
        blockchain: Project.infrastructure_to_blockchain("BNB"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: infrastructure} = selector) do
    {:error,
     "Invalid historical balance selector. The infrastructure #{inspect(infrastructure)} is not supported. Provided selector: #{
       inspect(selector)
     }"}
  end

  def selector_to_args(%{slug: slug} = selector) when not is_nil(slug) do
    with %{infrastructure: infrastructure} = map <- get_project_details(%{slug: slug}) do
      %{original_selector: selector} |> Map.merge(map)
    else
      {:error, {:missing_contract, _}} ->
        {:error,
         "Invalid historical balance selector. The provided slug has no contract data available. Provided selector: #{
           inspect(selector)
         }"}

      error ->
        error
    end
  end

  def selector_to_args(selector) do
    original_selector = Map.get(selector, :original_selector) || selector
    {:error, "Invalid historical balance selector: #{inspect(selector)}"}
  end

  defp get_project_details(%{contract: _, decimals: _, slug: _, infrastructure: _} = data) do
    data
  end

  defp get_project_details(%{slug: slug}) do
    with {:ok, contract, decimals, infrastructure} <-
           Project.contract_info_infrastructure_by_slug(slug) do
      %{contract: contract, decimals: decimals, slug: slug, infrastructure: infrastructure}
    end
  end
end
