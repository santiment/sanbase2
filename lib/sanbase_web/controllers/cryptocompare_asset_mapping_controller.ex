defmodule SanbaseWeb.CryptocompareAssetMappingController do
  @moduledoc """
  Serves the Santiment <-> Cryptocompare asset mapping as JSONEachRow.
  ClickHouse dictionaries are loaded from this endpoint.

  By default all mappings are returned. This is used by the
  `san_to_cryptocompare_asset_mapping` dictionary, keyed by slug, where every
  slug must resolve to its base asset (`p-uniswap` -> `UNI`).

  When the `unique_base_asset=true` query param is provided, only one slug per
  base asset is returned. This is used by the `cryptocompare_to_san_asset_mapping`
  dictionary, keyed by base asset. The slug is picked in the following order:
    - the slug without a multichain prefix (L1 asset or token on Ethereum);
    - the slug with a multichain prefix (`arb-uniswap`, `o-uniswap`, `p-uniswap`, etc.)
  """
  use SanbaseWeb, :controller

  alias Sanbase.Project
  require Logger

  def data(conn, params) do
    unique_base_asset? = params["unique_base_asset"] == "true"

    cache_key = {__MODULE__, __ENV__.function, unique_base_asset?} |> Sanbase.Cache.hash()
    data = Sanbase.Cache.get_or_store(cache_key, fn -> get_data(unique_base_asset?) end)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end

  defp get_data(unique_base_asset?) do
    Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
    |> Enum.reject(fn {cpc_slug, san_slug} ->
      # Sometimes the san_slug can be nil if the project is marked as deleted/duplicated
      is_nil(cpc_slug) or is_nil(san_slug)
    end)
    |> sort_assets()
    |> maybe_unique_base_asset(unique_base_asset?)
    |> Enum.map(fn {cpc_slug, san_slug} ->
      %{"base_asset" => cpc_slug, "slug" => san_slug} |> Jason.encode!()
    end)
    |> Enum.join("\n")
  end

  # The list is sorted by priority, so the first slug for every base asset is kept
  defp maybe_unique_base_asset(list, true),
    do: Enum.uniq_by(list, fn {cpc_slug, _} -> cpc_slug end)

  defp maybe_unique_base_asset(list, false), do: list

  # The prefix mapping keys include the trailing hyphen ("arb-", "o-", "p-", etc.),
  # but the prefix obtained after splitting the slug by "-" does not.
  @prefixes Sanbase.Project.Multichain.prefix_mapping()
            |> Map.keys()
            |> Enum.map(&String.trim_trailing(&1, "-"))
  # xrp before ripple
  # Ethereum asset before assets on other chains (with prefixes)
  defp sort_assets(list) do
    list
    |> Enum.sort_by(fn {_, value} ->
      case String.split(value, "-", parts: 2) do
        ["xrp" | _] -> {-1, value}
        [prefix, _] when prefix in @prefixes -> {1, value}
        _ -> {0, value}
      end
    end)
  end
end
