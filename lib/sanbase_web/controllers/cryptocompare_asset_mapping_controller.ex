defmodule SanbaseWeb.CryptocompareAssetMappingController do
  use SanbaseWeb, :controller

  alias Sanbase.Project
  require Logger

  def data(conn, _params) do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()
    data = Sanbase.Cache.get_or_store(cache_key, &get_data/0)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end

  defp get_data() do
    Project.SourceSlugMapping.get_source_slug_mappings("cryptocompare")
    |> Enum.reject(fn {cpc_slug, san_slug} ->
      # Sometimes the san_slug can be nil if the project is marked as deleted/duplicated
      is_nil(cpc_slug) or is_nil(san_slug)
    end)
    |> sort_assets()
    |> Enum.map(fn {cpc_slug, san_slug} ->
      %{"base_asset" => cpc_slug, "slug" => san_slug} |> Jason.encode!()
    end)
    |> Enum.join("\n")
  end

  # xrp before ripple
  # Ethereum asset before assets on other chains (with prefixes)
  defp sort_assets(list) do
    list
    |> Enum.sort_by(fn {_, value} ->
      case String.split(value, "-", parts: 2) do
        ["xrp" | _] -> {-1, value}
        [prefix, _] when prefix in ["a", "p", "o", "bnb", "arb", "sol", "aave"] -> {1, value}
        _ -> {0, value}
      end
    end)
  end
end
