defmodule Sanbase.Billing.Plan.Bundle.PackageSnapshotTest do
  @moduledoc ~s"""
  What each package contains, and the guarantee that publishing is the only thing
  that can change it.

  The interesting cases here are not the happy path but the two ways this design
  can go wrong:

    * a category name that no longer exists would silently sell an empty package
    * a metric that sits in two categories must be reachable through both, and
      through neither of the others - the dual-membership leak check from task PD
  """

  use Sanbase.DataCase, async: false

  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.MetricRegistryHelpers

  setup do
    # One category per package, named exactly as the definitions expect. If a
    # name here has to change, so does Package.all/0 - that coupling is the point.
    categories =
      Package.all()
      |> Enum.with_index()
      |> Map.new(fn {package, index} ->
        {:ok, category} =
          MetricCategory.create(%{name: package.category, display_order: index})

        {package.slug, category}
      end)

    %{categories: categories}
  end

  describe "materialize/0" do
    test "puts each category's metrics under its package", %{categories: categories} do
      categorize("bundle_test_price", categories["market"])
      categorize("bundle_test_dev_activity", categories["development"])

      {:ok, contents} = PackageSnapshot.materialize()

      assert contents["market"] == ["bundle_test_price"]
      assert contents["development"] == ["bundle_test_dev_activity"]
      assert contents["social"] == []
    end

    test "has an entry for every package, even the empty ones" do
      {:ok, contents} = PackageSnapshot.materialize()

      assert Map.keys(contents) |> Enum.sort() == Enum.sort(Package.slugs())
    end

    test "expands a template metric into the concrete names it stands for", %{
      categories: categories
    } do
      # Access checks are made against concrete names, so a snapshot holding the
      # template would grant access to nothing that can actually be requested.
      registry =
        MetricRegistryHelpers.create_registry_metric(%{
          metric: "bundle_test_social_volume_{{source}}",
          internal_metric: "bundle_test_social_volume_{{source}}_internal",
          is_template: true,
          parameters: [%{"source" => "twitter"}, %{"source" => "reddit"}]
        })

      map_registry(registry, categories["social"])

      {:ok, contents} = PackageSnapshot.materialize()

      assert contents["social"] == [
               "bundle_test_social_volume_reddit",
               "bundle_test_social_volume_twitter"
             ]
    end

    test "leaves out deprecated and hidden metrics", %{categories: categories} do
      categorize("bundle_test_kept", categories["market"])
      categorize(%{metric: "bundle_test_deprecated", is_deprecated: true}, categories["market"])
      categorize(%{metric: "bundle_test_hidden", is_hidden: true}, categories["market"])

      {:ok, contents} = PackageSnapshot.materialize()

      assert contents["market"] == ["bundle_test_kept"]
    end

    test "includes metrics served by adapter modules rather than the registry", %{
      categories: categories
    } do
      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Price.MetricAdapter",
          metric: "bundle_test_code_metric",
          category_id: categories["market"].id
        })

      {:ok, contents} = PackageSnapshot.materialize()

      assert contents["market"] == ["bundle_test_code_metric"]
    end

    test "refuses to build when a package's category is missing", %{categories: categories} do
      Sanbase.Repo.delete!(categories["market"])

      assert {:error, message} = PackageSnapshot.materialize()

      assert message =~ "market"
      assert message =~ "Market"
      # The message lists what does exist, so a rename is diagnosable without
      # opening the database.
      assert message =~ "Social"
    end
  end

  describe "publish/1" do
    test "numbers versions from one and increments", %{categories: categories} do
      categorize("bundle_test_first", categories["market"])

      assert {:ok, %{version: 1}} = PackageSnapshot.publish()

      categorize("bundle_test_second", categories["market"])

      assert {:ok, %{version: 2, contents: contents}} =
               PackageSnapshot.publish(notes: "added one")

      assert contents["market"] == ["bundle_test_first", "bundle_test_second"]
      assert PackageSnapshot.latest().version == 2
      assert PackageSnapshot.latest().notes == "added one"
      assert PackageSnapshot.by_version(1).contents["market"] == ["bundle_test_first"]
    end

    test "an earlier version is unaffected by later categorization", %{categories: categories} do
      # This is the whole reason snapshots exist: a customer pinned to version 1
      # keeps version 1's list no matter what admins do afterwards.
      categorize("bundle_test_sold", categories["market"])
      {:ok, published} = PackageSnapshot.publish()

      mapping_to_move = categorize("bundle_test_moved_later", categories["market"])

      {:ok, _} =
        MetricCategoryMapping.update(mapping_to_move, %{category_id: categories["social"].id})

      assert PackageSnapshot.by_version(published.version).contents["market"] == [
               "bundle_test_sold"
             ]
    end
  end

  describe "pending_changes/0" do
    test "is empty when the published snapshot matches the live categorization", %{
      categories: categories
    } do
      categorize("bundle_test_stable", categories["market"])
      {:ok, _} = PackageSnapshot.publish()

      assert {:ok, changes} = PackageSnapshot.pending_changes()
      assert changes == %{}
    end

    test "names what a publish would add and remove", %{categories: categories} do
      mapping = categorize("bundle_test_leaving", categories["market"])
      {:ok, _} = PackageSnapshot.publish()

      categorize("bundle_test_arriving", categories["market"])
      Sanbase.Repo.delete!(mapping)

      assert {:ok, changes} = PackageSnapshot.pending_changes()

      assert changes == %{
               "market" => %{
                 added: ["bundle_test_arriving"],
                 removed: ["bundle_test_leaving"]
               }
             }
    end

    test "before anything is published, everything reads as added", %{categories: categories} do
      categorize("bundle_test_new", categories["market"])

      assert {:ok, changes} = PackageSnapshot.pending_changes()
      assert changes["market"] == %{added: ["bundle_test_new"], removed: []}
    end
  end

  describe "metrics_for/2 - the dual-membership leak check" do
    setup %{categories: categories} do
      # bundle_test_nft_volume is deliberately in both Market and On-chain Labels,
      # which the Notion task asks for. bundle_test_whale_flow is only in
      # On-chain Labels.
      shared = MetricRegistryHelpers.create_registry_metric("bundle_test_nft_volume")
      map_registry(shared, categories["market"])
      map_registry(shared, categories["onchain_labels"])

      categorize("bundle_test_whale_flow", categories["onchain_labels"])
      categorize("bundle_test_price", categories["market"])

      {:ok, snapshot} = PackageSnapshot.publish()

      %{snapshot: snapshot}
    end

    test "a dual-membership metric is reachable through either package", %{snapshot: snapshot} do
      assert "bundle_test_nft_volume" in PackageSnapshot.metrics_for(snapshot, ["market"])

      assert "bundle_test_nft_volume" in PackageSnapshot.metrics_for(snapshot, ["onchain_labels"])
    end

    test "buying Market does not leak the Onchain-only metric", %{snapshot: snapshot} do
      market_only = PackageSnapshot.metrics_for(snapshot, ["market"])

      assert market_only == ["bundle_test_nft_volume", "bundle_test_price"]
      refute "bundle_test_whale_flow" in market_only
    end

    test "buying an unrelated package leaks nothing at all", %{snapshot: snapshot} do
      assert PackageSnapshot.metrics_for(snapshot, ["social"]) == []
    end

    test "buying both packages unions them without duplicating the shared metric", %{
      snapshot: snapshot
    } do
      both = PackageSnapshot.metrics_for(snapshot, ["market", "onchain_labels"])

      assert both == [
               "bundle_test_nft_volume",
               "bundle_test_price",
               "bundle_test_whale_flow"
             ]
    end

    test "an unknown package contributes nothing rather than raising", %{snapshot: snapshot} do
      # A snapshot published before a package existed genuinely has no list for
      # it. Re-resolving against a newer snapshot is the fix, not raising here.
      assert PackageSnapshot.metrics_for(snapshot, ["not_a_package"]) == []

      assert PackageSnapshot.metrics_for(snapshot, ["market", "not_a_package"]) ==
               PackageSnapshot.metrics_for(snapshot, ["market"])
    end
  end

  describe "Package definitions" do
    test "slugs are unique and stable" do
      slugs = Package.slugs()

      assert length(Enum.uniq(slugs)) == length(slugs)
      assert Package.valid_slug?("market")
      refute Package.valid_slug?("Market")
      refute Package.valid_slug?(:market)
    end

    test "an unknown slug reports what is known" do
      assert {:error, message} = Package.by_slug("premium")
      assert message =~ "market"
    end
  end

  defp categorize(metric, category) do
    registry =
      case metric do
        name when is_binary(name) -> MetricRegistryHelpers.create_registry_metric(name)
        attrs when is_map(attrs) -> MetricRegistryHelpers.create_registry_metric(attrs)
      end

    map_registry(registry, category)
  end

  defp map_registry(registry, category) do
    {:ok, mapping} =
      MetricCategoryMapping.create(%{
        metric_registry_id: registry.id,
        category_id: category.id
      })

    mapping
  end
end
