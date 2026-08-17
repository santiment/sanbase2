defmodule Sanbase.Metric.MetricReplaceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.Metric.MetricReplace

  describe "non-crypto assets" do
    test "the price and volume metrics are replaced" do
      insert(:non_crypto_asset, slug: "micron", asset_type: :stock)

      assert maybe_replace_metric("price_usd", %{slug: "micron"}) == "price_usd_5m"
      assert maybe_replace_metric("volume_usd", %{slug: "micron"}) == "volume_usd_5m"
    end

    test "hidden assets are replaced as well" do
      insert(:non_crypto_asset, slug: "micron", is_hidden: true)

      assert maybe_replace_metric("price_usd", %{slug: "micron"}) == "price_usd_5m"
    end

    test "other metrics are not replaced" do
      insert(:non_crypto_asset, slug: "micron")

      assert maybe_replace_metric("marketcap_usd", %{slug: "micron"}) == "marketcap_usd"
    end

    test "the legacy slugs are replaced without a DB record" do
      assert maybe_replace_metric("price_usd", %{slug: "s-and-p-500"}) == "price_usd_5m"
      assert maybe_replace_metric("volume_usd", %{slug: "ibit"}) == "volume_usd_5m"
    end
  end

  describe "sources stored in asset_prices_v3" do
    test "hyperliquid is not replaced" do
      insert(:non_crypto_asset, slug: "micron")

      selector = %{slug: "micron", source: "hyperliquid"}
      assert maybe_replace_metric("price_usd", selector) == "price_usd"
      assert maybe_replace_metric("volume_usd", selector) == "volume_usd"
    end

    test "cryptocompare is not replaced" do
      selector = %{slug: "s-and-p-500", source: "cryptocompare"}
      assert maybe_replace_metric("price_usd", selector) == "price_usd"
    end

    test "coinmarketcap is replaced" do
      selector = %{slug: "s-and-p-500", source: "coinmarketcap"}
      assert maybe_replace_metric("price_usd", selector) == "price_usd_5m"
    end
  end

  describe "other selectors" do
    test "a project slug is not replaced" do
      insert(:random_project, slug: "bitcoin")

      assert maybe_replace_metric("price_usd", %{slug: "bitcoin"}) == "price_usd"
    end

    test "a selector without a slug is not replaced" do
      assert maybe_replace_metric("price_usd", %{text: "some text"}) == "price_usd"
    end
  end

  describe "maybe_replace_metrics/2" do
    test "replaces every metric in the list" do
      insert(:non_crypto_asset, slug: "micron")

      assert maybe_replace_metrics(["price_usd", "volume_usd", "mvrv_usd"], %{slug: "micron"}) ==
               ["price_usd_5m", "volume_usd_5m", "mvrv_usd"]
    end

    test "keeps the list intact for a hyperliquid source" do
      insert(:non_crypto_asset, slug: "micron")

      metrics = ["price_usd", "volume_usd"]
      assert maybe_replace_metrics(metrics, %{slug: "micron", source: "hyperliquid"}) == metrics
    end
  end
end
