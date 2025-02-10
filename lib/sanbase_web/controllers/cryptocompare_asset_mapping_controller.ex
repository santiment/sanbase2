defmodule SanbaseWeb.CryptocompareAssetMappingController do
  use SanbaseWeb, :controller

  alias Sanbase.Project

  require Logger

  def data(conn, _params) do
    cache_key = Sanbase.Cache.hash({__MODULE__, __ENV__.function})
    data = Sanbase.Cache.get_or_store(cache_key, &get_data/0)

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.send_resp(200, data)
  end

  defp get_data do
    "cryptocompare"
    |> Project.SourceSlugMapping.get_source_slug_mappings()
    |> Enum.reject(fn {cpc_slug, san_slug} ->
      # Sometimes the san_slug can be nil if the project is marked as deleted/duplicated
      is_nil(cpc_slug) or is_nil(san_slug)
    end)
    |> sort_assets()
    |> Enum.map_join("\n", fn {cpc_slug, san_slug} ->
      Jason.encode!(%{"base_asset" => cpc_slug, "slug" => san_slug})
    end)
  end

  # xrp before ripple
  # Ethereum asset before assets on other chains (with prefixes)
  def sort_assets(list) do
    Enum.sort_by(list, fn {_, value} ->
      case String.split(value, "-", parts: 2) do
        ["xrp" | _] -> {-1, value}
        [prefix, _] when prefix in ["a", "p", "o", "bnb", "arb"] -> {1, value}
        _ -> {0, value}
      end
    end)
  end
end
