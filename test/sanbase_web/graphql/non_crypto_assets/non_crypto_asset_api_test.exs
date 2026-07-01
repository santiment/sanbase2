defmodule SanbaseWeb.Graphql.NonCryptoAssetApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    gold =
      insert(:non_crypto_asset,
        slug: "gold",
        name: "Gold",
        ticker: "XAU",
        asset_type: :commodity
      )

    sp500 = insert(:non_crypto_asset, slug: "sp500", name: "S&P 500", asset_type: :index)
    insert(:non_crypto_asset, slug: "hidden-asset", name: "Hidden", is_hidden: true)

    %{conn: build_conn(), gold: gold, sp500: sp500}
  end

  test "allNonCryptoAssets returns visible assets", context do
    query = """
    {
      allNonCryptoAssets {
        slug
        name
        ticker
        assetType
      }
    }
    """

    assets = execute_query(context.conn, query, "allNonCryptoAssets")

    assert %{
             "slug" => "gold",
             "name" => "Gold",
             "ticker" => "XAU",
             "assetType" => "COMMODITY"
           } in assets

    assert Enum.find(assets, &(&1["slug"] == "sp500"))
    refute Enum.find(assets, &(&1["slug"] == "hidden-asset"))
  end

  test "allNonCryptoAssets filters by asset type", context do
    query = """
    {
      allNonCryptoAssets(assetType: INDEX) {
        slug
      }
    }
    """

    assert [%{"slug" => "sp500"}] = execute_query(context.conn, query, "allNonCryptoAssets")
  end

  test "nonCryptoAssetBySlug returns the asset", context do
    query = """
    {
      nonCryptoAssetBySlug(slug: "gold") {
        slug
        name
        assetType
      }
    }
    """

    assert %{"slug" => "gold", "name" => "Gold", "assetType" => "COMMODITY"} =
             execute_query(context.conn, query, "nonCryptoAssetBySlug")
  end

  test "nonCryptoAssetBySlug returns an error for unknown slug", context do
    query = """
    {
      nonCryptoAssetBySlug(slug: "unknown") {
        slug
      }
    }
    """

    error_msg = execute_query_with_error(context.conn, query, "nonCryptoAssetBySlug")

    assert error_msg =~ "Non-crypto asset with slug unknown not found"
  end

  test "nonCryptoAssetBySlug does not expose hidden assets", context do
    query = """
    {
      nonCryptoAssetBySlug(slug: "hidden-asset") {
        slug
      }
    }
    """

    error_msg = execute_query_with_error(context.conn, query, "nonCryptoAssetBySlug")

    assert error_msg =~ "Non-crypto asset with slug hidden-asset is hidden"
  end
end
