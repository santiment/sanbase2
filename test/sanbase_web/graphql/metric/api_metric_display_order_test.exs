defmodule SanbaseWeb.Graphql.ApiMetricDisplayOrderTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, category1} =
      Sanbase.Metric.UIMetadata.Category.create(%{name: "Financial", display_order: 1})

    {:ok, category2} =
      Sanbase.Metric.UIMetadata.Category.create(%{name: "On-chain", display_order: 2})

    {:ok, group1} =
      Sanbase.Metric.UIMetadata.Group.create(%{
        name: "Price",
        category_id: category1.id
      })

    {:ok, group2} =
      Sanbase.Metric.UIMetadata.Group.create(%{
        name: "Network Activity",
        category_id: category2.id
      })

    {:ok, metric1} =
      Sanbase.Metric.UIMetadata.DisplayOrder.add_metric(
        "price_usd",
        category1.id,
        group1.id,
        ui_human_readable_name: "Price USD",
        chart_style: "line",
        unit: "usd",
        description: "USD price of the asset",
        type: "metric"
      )

    {:ok, metric2} =
      Sanbase.Metric.UIMetadata.DisplayOrder.add_metric(
        "price_btc",
        category1.id,
        group1.id,
        ui_human_readable_name: "Price BTC",
        chart_style: "line",
        unit: "btc",
        description: "BTC price of the asset",
        type: "metric"
      )

    {:ok, metric3} =
      Sanbase.Metric.UIMetadata.DisplayOrder.add_metric(
        "active_addresses_24h",
        category2.id,
        group2.id,
        ui_human_readable_name: "Active Addresses 24h",
        chart_style: "bar",
        unit: "",
        description: "Number of active addresses in the last 24 hours",
        type: "metric"
      )

    {:ok, metric4} =
      Sanbase.Metric.UIMetadata.DisplayOrder.add_metric(
        "transaction_volume",
        category2.id,
        group2.id,
        ui_human_readable_name: "Transaction Volume",
        chart_style: "area",
        unit: "usd",
        description: "Transaction volume in USD",
        type: "metric"
      )

    %{
      conn: conn,
      user: user,
      category1: category1,
      category2: category2,
      metric1: metric1,
      metric2: metric2,
      metric3: metric3,
      metric4: metric4
    }
  end

  test "get ordered metrics works properly", %{conn: conn} do
    query = """
    {
      getOrderedMetrics {
        categories
        metrics {
          metric
          type
          uiHumanReadableName
          categoryName
          groupName
          chartStyle
          unit
          description
          args
          isNew
          displayOrder
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "getOrderedMetrics"))
      |> json_response(200)
      |> get_in(["data", "getOrderedMetrics"])

    assert result["categories"] == ["Financial", "On-chain"]

    metrics = result["metrics"]
    assert length(metrics) == 4

    financial_metrics = Enum.filter(metrics, &(&1["categoryName"] == "Financial"))
    onchain_metrics = Enum.filter(metrics, &(&1["categoryName"] == "On-chain"))

    assert length(financial_metrics) == 2
    assert length(onchain_metrics) == 2

    price_usd = Enum.find(metrics, &(&1["metric"] == "price_usd"))
    price_btc = Enum.find(metrics, &(&1["metric"] == "price_btc"))

    assert price_usd["uiHumanReadableName"] == "Price USD"
    assert price_usd["groupName"] == "Price"
    assert price_usd["chartStyle"] == "line"
    assert price_usd["unit"] == "usd"

    assert price_btc["uiHumanReadableName"] == "Price BTC"
    assert price_btc["categoryName"] == "Financial"
    assert price_btc["unit"] == "btc"

    active_addresses = Enum.find(metrics, &(&1["metric"] == "active_addresses_24h"))
    transaction_volume = Enum.find(metrics, &(&1["metric"] == "transaction_volume"))

    assert active_addresses["uiHumanReadableName"] == "Active Addresses 24h"
    assert active_addresses["categoryName"] == "On-chain"
    assert active_addresses["groupName"] == "Network Activity"

    assert transaction_volume["uiHumanReadableName"] == "Transaction Volume"
    assert transaction_volume["categoryName"] == "On-chain"
    assert transaction_volume["chartStyle"] == "area"
    assert transaction_volume["unit"] == "usd"

    financial_display_orders = Enum.map(financial_metrics, & &1["displayOrder"])
    onchain_display_orders = Enum.map(onchain_metrics, & &1["displayOrder"])

    assert Enum.sort(financial_display_orders) == financial_display_orders
    assert Enum.sort(onchain_display_orders) == onchain_display_orders
  end

  test "get metrics by category works properly", %{conn: conn} do
    query = """
    {
      getMetricsByCategory(category: "Financial") {
        metric
        type
        uiHumanReadableName
        categoryName
        groupName
        chartStyle
        unit
        description
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "getMetricsByCategory"))
      |> json_response(200)
      |> get_in(["data", "getMetricsByCategory"])

    assert length(result) == 2
    metric = List.first(result)
    assert metric["metric"] == "price_usd"
    assert metric["uiHumanReadableName"] == "Price USD"
    assert metric["categoryName"] == "Financial"
    assert metric["groupName"] == "Price"
  end

  test "get metrics by category and group works properly", %{conn: conn} do
    query = """
    {
      getMetricsByCategoryAndGroup(category: "On-chain", group: "Network Activity") {
        metric
        type
        uiHumanReadableName
        categoryName
        groupName
        chartStyle
        unit
        description
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "getMetricsByCategoryAndGroup"))
      |> json_response(200)
      |> get_in(["data", "getMetricsByCategoryAndGroup"])

    assert length(result) == 2
    metric = List.first(result)
    assert metric["metric"] == "active_addresses_24h"
    assert metric["uiHumanReadableName"] == "Active Addresses 24h"
    assert metric["categoryName"] == "On-chain"
    assert metric["groupName"] == "Network Activity"
  end

  test "reordering metrics works properly", %{
    conn: conn,
    category1: category1,
    metric1: metric1,
    metric2: metric2
  } do
    # Fetch initial state directly from database
    metrics_before =
      Sanbase.Metric.UIMetadata.DisplayOrder.by_category(category1.id)
      |> Enum.sort_by(& &1.display_order)

    # Get the metrics we're interested in
    price_usd_before = Enum.find(metrics_before, &(&1.metric == "price_usd"))
    price_btc_before = Enum.find(metrics_before, &(&1.metric == "price_btc"))

    # Verify initial ordering (price_usd should be first)
    assert price_usd_before.display_order < price_btc_before.display_order

    # Now reorder the metrics
    new_order = [
      # Increase price_usd display_order to 10
      %{metric_id: metric1.id, display_order: 10},
      # Set price_btc display_order to 5
      %{metric_id: metric2.id, display_order: 5}
    ]

    # Apply the reordering
    assert {:ok, :ok} =
             Sanbase.Metric.UIMetadata.DisplayOrder.reorder_metrics(category1.id, new_order)

    # Verify directly in the database that the records were updated
    price_usd_db = Sanbase.Repo.get(Sanbase.Metric.UIMetadata.DisplayOrder, metric1.id)
    price_btc_db = Sanbase.Repo.get(Sanbase.Metric.UIMetadata.DisplayOrder, metric2.id)

    # Verify the reordering worked in the database
    assert price_btc_db.display_order < price_usd_db.display_order
    assert price_btc_db.display_order == 5
    assert price_usd_db.display_order == 10

    # Now fetch all metrics for this category again from DB to verify order
    metrics_after =
      Sanbase.Metric.UIMetadata.DisplayOrder.by_category(category1.id)
      |> Enum.sort_by(& &1.display_order)

    # First metric should now be price_btc
    first_metric = List.first(metrics_after)
    assert first_metric.metric == "price_btc"
    assert first_metric.display_order == 5

    query_api = """
    {
      getOrderedMetrics {
        metrics {
          metric
          categoryName
          displayOrder
        }
      }
    }
    """

    api_result =
      conn
      |> post("/graphql", query_skeleton(query_api, "getOrderedMetrics"))
      |> json_response(200)
      |> get_in(["data", "getOrderedMetrics", "metrics"])

    assert api_result == [
             %{"categoryName" => "Financial", "displayOrder" => 5, "metric" => "price_btc"},
             %{
               "categoryName" => "Financial",
               "displayOrder" => 10,
               "metric" => "price_usd"
             },
             %{
               "categoryName" => "On-chain",
               "displayOrder" => 1,
               "metric" => "active_addresses_24h"
             },
             %{
               "categoryName" => "On-chain",
               "displayOrder" => 2,
               "metric" => "transaction_volume"
             }
           ]
  end
end
