defmodule Sanbase.Hyperliquid.Bbo.MetricAdapterTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Hyperliquid.Bbo.MetricAdapter, as: BboMetricAdapter
  alias Sanbase.Metric

  describe "get_module/2 routing" do
    test "price_usd with a hyperliquid source goes to the BBO adapter" do
      selector = %{slug: "micron", source: "hyperliquid"}

      assert Metric.get_module("price_usd", selector: selector) == BboMetricAdapter
    end

    test "the source can also come from the opts" do
      opts = [source: "hyperliquid"]
      selector = %{slug: "micron"}

      assert Metric.get_module("price_usd", selector: selector, opts: opts) == BboMetricAdapter
    end

    test "price_usd without a source does not go to the BBO adapter" do
      selector = %{slug: "micron"}

      assert Metric.get_module("price_usd", selector: selector) == Sanbase.Price.MetricAdapter
    end

    test "cryptocompare keeps going to the price pair adapter" do
      selector = %{slug: "micron", source: "cryptocompare"}

      assert Metric.get_module("price_usd", selector: selector) ==
               Sanbase.PricePair.MetricAdapter
    end

    test "the BBO adapter serves price_usd only" do
      selector = %{slug: "micron", source: "hyperliquid"}

      refute Metric.get_module("volume_usd", selector: selector) == BboMetricAdapter
      refute Metric.get_module("marketcap_usd", selector: selector) == BboMetricAdapter
      refute Metric.get_module("price_btc", selector: selector) == BboMetricAdapter
    end
  end

  describe "available_slugs/0" do
    test "returns the projects and non-crypto assets mapped to a hyperliquid coin" do
      Sanbase.Cache.clear_all()

      project = insert(:random_project)
      asset = insert(:non_crypto_asset, slug: "gold")

      insert(:source_slug_mapping, source: "hyperliquid", slug: "BTC", project: project)

      insert(:source_slug_mapping,
        source: "hyperliquid",
        slug: "GOLD",
        project: nil,
        non_crypto_asset: asset
      )

      # Comes with a coinmarketcap mapping only, so it must not show up
      insert(:random_project)

      assert {:ok, slugs} = BboMetricAdapter.available_slugs()
      assert Enum.sort(slugs) == Enum.sort([project.slug, "gold"])
    end
  end

  describe "metadata/1" do
    test "last is the only aggregation" do
      assert {:ok, metadata} = BboMetricAdapter.metadata("price_usd")

      assert metadata.available_aggregations == [:last]
      assert metadata.default_aggregation == :last
      assert metadata.required_selectors == [:slug]
    end
  end
end
