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
    |> Enum.map(fn {cpc_slug, san_slug} ->
      %{"base_asset" => cpc_slug, "slug" => san_slug} |> Jason.encode!()
    end)
    |> Enum.join("\n")
  end
end
