defmodule Sanbase.Metric.UIMetadata.DisplayOrder.ReorderTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Metric.UIMetadata.DisplayOrder.Reorder
  alias Sanbase.Metric.UIMetadata.{Category, Group, DisplayOrder}

  setup do
    # Create test data
    {:ok, category1} = Category.create(%{name: "Financial", display_order: 1})
    {:ok, category2} = Category.create(%{name: "On-chain", display_order: 2})

    {:ok, group1} = Group.create(%{name: "Price", category_id: category1.id})
    {:ok, group2} = Group.create(%{name: "Volume", category_id: category1.id})
    {:ok, group3} = Group.create(%{name: "Network Activity", category_id: category2.id})

    # Create some metrics with specific display orders
    {:ok, metric1} =
      DisplayOrder.add_metric(
        "price_usd",
        category1.id,
        group1.id,
        ui_human_readable_name: "Price USD",
        chart_style: "line",
        unit: "usd"
      )

    # Manually update display_order to a specific value (5)
    {:ok, _} = DisplayOrder.do_update(metric1, %{display_order: 5})
    metric1 = DisplayOrder.by_id(metric1.id)

    {:ok, metric2} =
      DisplayOrder.add_metric(
        "price_btc",
        category1.id,
        group1.id,
        ui_human_readable_name: "Price BTC",
        chart_style: "line",
        unit: "btc"
      )

    # Manually update display_order to a specific value (10)
    {:ok, _} = DisplayOrder.do_update(metric2, %{display_order: 10})
    metric2 = DisplayOrder.by_id(metric2.id)

    # Add metric in a different group but same category
    {:ok, metric3} =
      DisplayOrder.add_metric(
        "trading_volume",
        category1.id,
        group2.id,
        ui_human_readable_name: "Trading Volume",
        chart_style: "bar",
        unit: "usd"
      )

    # Manually update display_order to a specific value (15)
    {:ok, _} = DisplayOrder.do_update(metric3, %{display_order: 15})
    metric3 = DisplayOrder.by_id(metric3.id)

    # Add metric in a different category
    {:ok, metric4} =
      DisplayOrder.add_metric(
        "active_addresses_24h",
        category2.id,
        group3.id,
        ui_human_readable_name: "Active Addresses 24h",
        chart_style: "bar",
        unit: ""
      )

    # Manually update display_order to a specific value (3)
    {:ok, _} = DisplayOrder.do_update(metric4, %{display_order: 3})
    metric4 = DisplayOrder.by_id(metric4.id)

    # Collect all metrics
    metrics = DisplayOrder.all()

    %{
      category1: category1,
      category2: category2,
      group1: group1,
      group2: group2,
      group3: group3,
      metrics: metrics,
      metric1: metric1,
      metric2: metric2,
      metric3: metric3,
      metric4: metric4
    }
  end

  describe "prepare_reordering/2" do
    test "correctly prepares reordering data for valid IDs", %{
      metrics: metrics,
      metric1: metric1,
      metric2: metric2,
      metric3: metric3,
      category1: category1
    } do
      # Simulate UI providing IDs in a new order: price_btc, price_eth, price_usd
      ids = [
        "metric-#{metric2.id}",
        "metric-#{metric3.id}",
        "metric-#{metric1.id}"
      ]

      {:ok, cat_id, new_order} = Reorder.prepare_reordering(ids, metrics)

      # Verify basics
      assert cat_id == category1.id
      assert length(new_order) == 3

      # New display order should match the position in the list (1-based)
      btc_order = Enum.find(new_order, &(&1.metric_id == metric2.id))
      volume_order = Enum.find(new_order, &(&1.metric_id == metric3.id))
      usd_order = Enum.find(new_order, &(&1.metric_id == metric1.id))

      # The original display orders were: 5, 10, 15
      # After reordering, the sorted values should be assigned in the new order: 5, 10, 15
      assert btc_order.display_order == 5
      assert volume_order.display_order == 10
      assert usd_order.display_order == 15
    end

    test "preserves display_order values within a category when reordering a subset (group)", %{
      metrics: metrics,
      metric1: metric1,
      metric2: metric2,
      category1: category1
    } do
      # Filter down to just metrics in group1 (price_usd and price_btc)
      group1_metrics = Enum.filter(metrics, &(&1.group_id == metric1.group_id))

      # Simulate UI providing IDs in reversed order: price_btc, then price_usd
      ids = [
        "metric-#{metric2.id}",
        "metric-#{metric1.id}"
      ]

      {:ok, cat_id, new_order} = Reorder.prepare_reordering(ids, group1_metrics)

      # Verify basics
      assert cat_id == category1.id
      assert length(new_order) == 2

      # The original display orders for these metrics were: 5 (usd), 10 (btc)
      # When we swap them, btc should get 5, and usd should get 10
      btc_order = Enum.find(new_order, &(&1.metric_id == metric2.id))
      usd_order = Enum.find(new_order, &(&1.metric_id == metric1.id))

      # Was 10
      assert btc_order.display_order == 5
      # Was 5
      assert usd_order.display_order == 10
    end

    test "returns error for empty ID list", %{metrics: metrics} do
      assert {:error, _} = Reorder.prepare_reordering([], metrics)
    end

    test "returns error for IDs that don't match metrics", %{metrics: metrics} do
      ids = ["metric-999999"]
      assert {:error, _} = Reorder.prepare_reordering(ids, metrics)
    end
  end

  describe "apply_reordering/2" do
    test "successfully applies reordering", %{
      metrics: _metrics,
      metric1: metric1,
      metric2: metric2,
      category1: category1
    } do
      # Build a reordering that swaps metric1 and metric2
      new_order = [
        %{metric_id: metric1.id, display_order: 10},
        %{metric_id: metric2.id, display_order: 5}
      ]

      assert {:ok, :ok} = Reorder.apply_reordering(category1.id, new_order)

      # Verify DB changes
      updated_metrics =
        DisplayOrder.by_category(category1.id)
        |> Enum.sort_by(& &1.display_order)

      first_metric = List.first(updated_metrics)
      assert first_metric.id == metric2.id
      assert first_metric.display_order == 5

      second_metric = Enum.at(updated_metrics, 1)
      assert second_metric.id == metric1.id
      assert second_metric.display_order == 10
    end
  end

  describe "integration test" do
    test "prepare_reordering and apply_reordering work together preserving display_order values",
         %{
           metrics: metrics,
           metric1: metric1,
           metric2: metric2,
           metric3: metric3,
           category1: category1
         } do
      # Initial display orders: usd=5, btc=10, volume=15

      # Simulate UI providing IDs in reversed order: volume, btc, usd
      ids = [
        "metric-#{metric3.id}",
        "metric-#{metric2.id}",
        "metric-#{metric1.id}"
      ]

      # Prepare
      {:ok, cat_id, new_order} = Reorder.prepare_reordering(ids, metrics)

      # Apply
      assert {:ok, :ok} = Reorder.apply_reordering(cat_id, new_order)

      # Verify
      updated_metrics =
        DisplayOrder.by_category(category1.id)
        |> Enum.sort_by(& &1.display_order)

      # Order by display_order should now be: volume(5), btc(10), usd(15)
      assert Enum.at(updated_metrics, 0).id == metric3.id
      assert Enum.at(updated_metrics, 0).display_order == 5

      assert Enum.at(updated_metrics, 1).id == metric2.id
      assert Enum.at(updated_metrics, 1).display_order == 10

      assert Enum.at(updated_metrics, 2).id == metric1.id
      assert Enum.at(updated_metrics, 2).display_order == 15
    end

    test "all_ordered sorts by category display order and then metric display order regardless of group",
         %{
           metric1: metric1,
           metric2: metric2,
           metric3: metric3,
           metric4: metric4
         } do
      # Metrics:
      # - metric1: category1 (order=1), group1, display_order=5
      # - metric2: category1 (order=1), group1, display_order=10
      # - metric3: category1 (order=1), group2, display_order=15
      # - metric4: category2 (order=2), group3, display_order=3

      # Create two new metrics in a different group but with display_orders between the existing ones
      {:ok, new_category} = Category.create(%{name: "Financial 2", display_order: 1})
      {:ok, group_z} = Group.create(%{name: "ZGroup", category_id: new_category.id})

      {:ok, metric_z1} =
        DisplayOrder.add_metric(
          "z_metric_1",
          new_category.id,
          group_z.id,
          ui_human_readable_name: "Z Metric 1"
        )

      {:ok, _} = DisplayOrder.do_update(metric_z1, %{display_order: 7})

      {:ok, metric_z2} =
        DisplayOrder.add_metric(
          "z_metric_2",
          new_category.id,
          group_z.id,
          ui_human_readable_name: "Z Metric 2"
        )

      {:ok, _} = DisplayOrder.do_update(metric_z2, %{display_order: 12})

      # Now get all ordered metrics
      ordered_metrics = DisplayOrder.all_ordered()

      # Extract the metrics in order by ID
      metric_ids = Enum.map(ordered_metrics, & &1.id)

      # First should be all category1 metrics ordered by display_order
      # regardless of which group they're in
      category1_metrics = [metric1.id, metric_z1.id, metric2.id, metric_z2.id, metric3.id]

      # Then category2 metrics
      category2_metrics = [metric4.id]

      # Check if the first 5 metrics are the category1 metrics in the expected order
      assert Enum.take(metric_ids, 5) == category1_metrics

      # Check if the next metric is from category2
      assert Enum.at(metric_ids, 5) == List.first(category2_metrics)
    end
  end
end
