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

    {:ok, _} =
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

    {:ok, _} =
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

    {:ok, _} =
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

    {:ok, _} =
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

    %{conn: conn, user: user}
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
end
