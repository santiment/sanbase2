defmodule Sanbase.Billing.BundleAvailableMetricsTest do
  @moduledoc ~s"""
  Catalog browsing for bundle packages via `getAvailableMetrics`.

  `plan: BUNDLE` cannot answer from the plan name alone, so it requires
  `metricPackages`. Non-bundle plans must keep working exactly as before.
  """

  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping

  @moduletag capture_log: true

  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup do
    publish_snapshot()
    :ok
  end

  describe "backwards compatibility" do
    test "plan PRO is unchanged", %{conn: conn} do
      metrics = get_available_metrics(conn, %{plan: :pro, product: :sanapi})

      expected =
        AccessChecker.get_available_metrics_for_plan("PRO", "SANAPI")
        |> Enum.reject(&(&1 in Sanbase.Metric.hidden_metrics()))
        |> Enum.reject(&(&1 in Sanbase.Metric.experimental_metrics()))
        |> Enum.uniq()
        |> Enum.sort()

      assert metrics == expected
    end

    test "omitting plan still returns the full catalog", %{conn: conn} do
      query = """
      {
        getAvailableMetrics
      }
      """

      metrics = execute_query(conn, query, "getAvailableMetrics")

      assert is_list(metrics)
      assert "price_usd" in metrics
      assert length(metrics) > 100
    end
  end

  describe "plan BUNDLE with metricPackages" do
    test "returns the union of the requested packages", %{conn: conn} do
      metrics =
        get_available_metrics(conn, %{
          plan: :bundle,
          product: :sanapi,
          metric_packages: ["social", "market"]
        })

      assert "social_volume_total" in metrics
      assert "price_usd" in metrics
      refute "mvrv_usd" in metrics
      refute "dev_activity" in metrics
    end

    test "a single package returns only its metrics", %{conn: conn} do
      metrics =
        get_available_metrics(conn, %{
          plan: :bundle,
          product: :sanapi,
          metric_packages: ["social"]
        })

      assert metrics == ["social_volume_total"]
    end

    test "requires metricPackages", %{conn: conn} do
      error = get_available_metrics_error(conn, %{plan: :bundle, product: :sanapi})

      assert error =~ "metricPackages is required"
    end

    test "rejects an empty metricPackages list", %{conn: conn} do
      error =
        get_available_metrics_error(conn, %{
          plan: :bundle,
          product: :sanapi,
          metric_packages: []
        })

      assert error =~ "metricPackages is required"
    end

    test "rejects unknown package slugs", %{conn: conn} do
      error =
        get_available_metrics_error(conn, %{
          plan: :bundle,
          product: :sanapi,
          metric_packages: ["social", "not_a_package"]
        })

      assert error =~ "Unknown metric package"
      assert error =~ "not_a_package"
    end

    test "rejects metricPackages on a non-bundle plan", %{conn: conn} do
      error =
        get_available_metrics_error(conn, %{
          plan: :pro,
          product: :sanapi,
          metric_packages: ["social"]
        })

      assert error =~ "metricPackages is only valid with plan: BUNDLE"
    end

    test "rejects metricPackages without a plan", %{conn: conn} do
      error = get_available_metrics_error(conn, %{metric_packages: ["social"]})

      assert error =~ "metricPackages is only valid with plan: BUNDLE"
    end
  end

  defp get_available_metrics(conn, args) do
    query = """
    {
      getAvailableMetrics(#{map_to_args(args)})
    }
    """

    execute_query(conn, query, "getAvailableMetrics")
  end

  defp get_available_metrics_error(conn, args) do
    query = """
    {
      getAvailableMetrics(#{map_to_args(args)})
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    assert result["data"]["getAvailableMetrics"] == nil
    hd(result["errors"])["message"]
  end

  defp publish_snapshot do
    for {package, index} <- Enum.with_index(Bundle.Package.all()) do
      {:ok, category} =
        MetricCategory.create(%{name: package.category, display_order: index})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Metric.BundleAvailableMetricsTestAdapter",
          metric: Map.fetch!(@packaged_metrics, package.slug),
          category_id: category.id
        })
    end

    {:ok, snapshot} = PackageSnapshot.publish(notes: "test")
    snapshot
  end
end
