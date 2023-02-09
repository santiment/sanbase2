defmodule Sanbase.Clickhouse.HistoricalBalance do
  @moduledoc ~s"""
  Module providing functions for historical balances and balance changes.
  This module dispatches to underlaying modules and serves as common interface
  for many different database tables and schemas.
  """

  import Sanbase.Utils.Transform, only: [maybe_sort: 3]

  alias Sanbase.Project
  alias Sanbase.BlockchainAddress
  alias Sanbase.Clickhouse.HistoricalBalance.XrpBalance

  @balances_aggregated_blockchains [
    "ethereum",
    "bitcoin",
    "bitcoin-cash",
    "litecoin",
    "binance"
  ]

  @supported_infrastructures ["BCH", "BNB", "BEP2", "BTC", "LTC", "XRP", "ETH"]
  def supported_infrastructures(), do: @supported_infrastructures

  @type selector :: %{
          optional(:infrastructure) => String.t(),
          optional(:currency) => String.t(),
          optional(:slug) => String.t(),
          optional(:contract) => String.t(),
          optional(:decimals) => non_neg_integer()
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

  defguard balances_aggregated_blockchain?(blockchain)
           when blockchain in @balances_aggregated_blockchains

  @doc ~s"""
  Return a list of the assets that a given address currently holds or
  has held in the past.

  This can be combined with the historical balance query to see the historical
  balance of all currently owned assets
  """
  @spec assets_held_by_address(map(), Keyword.t()) ::
          {:ok, list(map())} | {:error, String.t()}
  def assets_held_by_address(%{infrastructure: infr, address: address}, opts \\ []) do
    case selector_to_args(%{infrastructure: infr}) do
      %{blockchain: blockchain}
      when balances_aggregated_blockchain?(blockchain) ->
        Sanbase.Balance.assets_held_by_address(address, opts)

      %{module: module} ->
        module.assets_held_by_address(address)

      {:error, error} ->
        {:error, error}
    end
    |> maybe_sort(:balance, :desc)
  end

  @doc ~s"""
  Return a list of the assets that a given address currently holds or
  has held in the past.

  This can be combined with the historical balance query to see the historical
  balance of all currently owned assets
  """
  @spec usd_value_address_change(map(), DateTime.t()) ::
          {:ok, list(map())} | {:error, String.t()}
  def usd_value_address_change(%{infrastructure: infr, address: address}, datetime) do
    case selector_to_args(%{infrastructure: infr}) do
      %{blockchain: blockchain}
      when balances_aggregated_blockchain?(blockchain) ->
        Sanbase.Balance.usd_value_address_change(address, datetime)

      %{module: module} ->
        module.usd_value_address_change(address, datetime)

      {:error, error} ->
        {:error, error}
    end
    |> maybe_sort(:usd_value_change, :desc)
  end

  @doc ~s"""
  Return a list of the assets that a given address currently holds or
  has held in the past.

  This can be combined with the historical balance query to see the historical
  balance of all currently owned assets
  """
  @spec usd_value_held_by_address(map()) ::
          {:ok, list(map())} | {:error, String.t()}
  def usd_value_held_by_address(%{infrastructure: infr, address: address}) do
    case selector_to_args(%{infrastructure: infr}) do
      %{blockchain: blockchain}
      when balances_aggregated_blockchain?(blockchain) ->
        Sanbase.Balance.usd_value_held_by_address(address)

      %{module: module} ->
        module.usd_value_held_by_address(address)

      {:error, error} ->
        {:error, error}
    end
    |> maybe_sort(:current_usd_value, :desc)
  end

  @doc ~s"""
  For a given address or list of addresses returns the `slug` balance change for the
  from-to period. The returned lists indicates the address, before balance, after balance
  and the balance change
  """
  @spec balance_change(
          selector,
          address,
          from :: DateTime.t(),
          to :: DateTime.t()
        ) ::
          __MODULE__.Behaviour.balance_change_result()

  def balance_change(selector, address, from, to) do
    case selector_to_args(selector) do
      %{blockchain: blockchain, slug: slug}
      when balances_aggregated_blockchain?(blockchain) ->
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
  @spec historical_balance(
          selector,
          address,
          from :: DateTime.t(),
          to :: DateTime.t(),
          interval
        ) ::
          __MODULE__.Behaviour.historical_balance_result()
  def historical_balance(selector, address, from, to, interval) do
    case selector_to_args(selector) do
      %{blockchain: blockchain, slug: slug}
      when balances_aggregated_blockchain?(blockchain) ->
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
      %{blockchain: blockchain, slug: slug}
      when balances_aggregated_blockchain?(blockchain) ->
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
                  (is_map_key(map, :infrastructure) and
                     not is_map_key(map, :slug) and
                     map.infrastructure == "ETH")

  def selector_to_args(
        %{infrastructure: "ETH", contract: contract, decimals: decimals} = selector
      )
      when is_binary(contract) and is_number(decimals) and decimals > 0 and
             not is_ethereum(selector) do
    %{
      module: :none,
      asset: String.downcase(contract),
      contract: String.downcase(contract),
      blockchain: BlockchainAddress.blockchain_from_infrastructure("ETH"),
      slug: Map.get(selector, :slug),
      decimals: decimals
    }
  end

  def selector_to_args(%{} = selector) when is_ethereum(selector) do
    selector = Map.put_new(selector, :slug, "ethereum")

    with %{
           slug: slug,
           contract: contract,
           decimals: decimals,
           infrastructure: "ETH"
         } <-
           get_project_details(selector) do
      %{
        module: :none,
        asset: contract,
        contract: contract,
        blockchain: BlockchainAddress.blockchain_from_infrastructure("ETH"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "ETH", slug: slug} = selector)
      when is_binary(slug) do
    with %{contract: contract, decimals: decimals} <-
           get_project_details(selector) do
      %{
        module: :none,
        asset: contract,
        contract: contract,
        blockchain: BlockchainAddress.blockchain_from_infrastructure("ETH"),
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
      blockchain: BlockchainAddress.blockchain_from_infrastructure("XRP"),
      slug: "xrp",
      decimals: 0
    }
  end

  def selector_to_args(%{infrastructure: "BTC"} = selector) do
    selector = Map.put_new(selector, :slug, "bitcoin")

    with %{slug: slug, contract: contract, decimals: decimals} <-
           get_project_details(selector) do
      %{
        module: :none,
        asset: contract,
        contract: contract,
        blockchain: BlockchainAddress.blockchain_from_infrastructure("BTC"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "BCH"} = selector) do
    selector = Map.put_new(selector, :slug, "bitcoin-cash")

    with %{slug: slug, contract: contract, decimals: decimals} <-
           get_project_details(selector) do
      %{
        module: :none,
        asset: contract,
        contract: contract,
        blockchain: BlockchainAddress.blockchain_from_infrastructure("BCH"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "LTC"} = selector) do
    selector = Map.put_new(selector, :slug, "litecoin")

    with %{slug: slug, contract: contract, decimals: decimals} <-
           get_project_details(selector) do
      %{
        module: :none,
        asset: contract,
        contract: contract,
        blockchain: BlockchainAddress.blockchain_from_infrastructure("LTC"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: "BNB"} = selector) do
    selector = Map.put_new(selector, :slug, "binance-coin")

    with %{slug: slug, contract: contract, decimals: decimals} <-
           get_project_details(selector) do
      %{
        module: :none,
        asset: contract,
        contract: contract,
        blockchain: BlockchainAddress.blockchain_from_infrastructure("BNB"),
        slug: slug,
        decimals: decimals
      }
    end
  end

  def selector_to_args(%{infrastructure: infrastructure} = selector) do
    {:error,
     "Invalid historical balance selector. The infrastructure #{inspect(infrastructure)} is not supported. Provided selector: #{inspect(selector)}"}
  end

  def selector_to_args(%{slug: slug} = selector) when not is_nil(slug) do
    with %{infrastructure: _} = map <- get_project_details(%{slug: slug}) do
      %{original_selector: selector} |> Map.merge(map) |> selector_to_args()
    else
      {:error, {:missing_contract, _}} ->
        {:error,
         "Invalid historical balance selector. The provided slug has no contract data available. Provided selector: #{inspect(selector)}"}

      error ->
        error
    end
  end

  def selector_to_args(selector) do
    original_selector = Map.get(selector, :original_selector) || selector

    {:error, "Invalid historical balance selector: #{inspect(original_selector)}"}
  end

  defp get_project_details(%{contract: _, decimals: _, slug: _, infrastructure: _} = data) do
    data
  end

  defp get_project_details(%{slug: slug}) do
    with {:ok, contract, decimals, infrastructure} <-
           Project.contract_info_infrastructure_by_slug(slug) do
      %{
        contract: contract,
        decimals: decimals,
        slug: slug,
        infrastructure: infrastructure
      }
    end
  end
end
