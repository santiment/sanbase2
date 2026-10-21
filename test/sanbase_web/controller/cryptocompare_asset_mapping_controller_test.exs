defmodule SanbaseWeb.CryptocompareAssetMappingControllerTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory

  setup do
    # Insert the prefixed projects first so the result does not depend on insertion order
    for {slug, base_asset} <- [
          {"p-uniswap", "UNI"},
          {"o-uniswap", "UNI"},
          {"arb-uniswap", "UNI"},
          {"uniswap", "UNI"},
          {"p-onlyl2", "ONLYL2"},
          {"arb-onlyl2", "ONLYL2"},
          {"ripple", "XRP"},
          {"xrp", "XRP"},
          {"bitcoin", "BTC"}
        ] do
      insert(:random_project,
        slug: slug,
        source_slug_mappings: [
          build(:source_slug_mapping, source: "cryptocompare", slug: base_asset)
        ]
      )
    end

    :ok
  end

  test "returns all mappings by default", %{conn: conn} do
    result = get_mapping(conn, "/cryptocompare_asset_mapping")

    assert length(result) == 9

    assert {"UNI", "uniswap"} in result
    assert {"UNI", "p-uniswap"} in result
    assert {"UNI", "o-uniswap"} in result
    assert {"UNI", "arb-uniswap"} in result
    assert {"ONLYL2", "p-onlyl2"} in result
    assert {"ONLYL2", "arb-onlyl2"} in result

    # The slug without a prefix comes before the slugs with prefixes
    uni_slugs = for {"UNI", slug} <- result, do: slug
    assert uni_slugs == ["uniswap", "arb-uniswap", "o-uniswap", "p-uniswap"]
  end

  test "returns one slug per base asset with unique_base_asset=true", %{conn: conn} do
    result = get_mapping(conn, "/cryptocompare_asset_mapping?unique_base_asset=true")

    assert Enum.sort(result) == [
             {"BTC", "bitcoin"},
             {"ONLYL2", "arb-onlyl2"},
             {"UNI", "uniswap"},
             {"XRP", "xrp"}
           ]
  end

  defp get_mapping(conn, path) do
    conn
    |> get(path)
    |> response(200)
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
    |> Enum.map(fn %{"base_asset" => base_asset, "slug" => slug} -> {base_asset, slug} end)
  end
end
