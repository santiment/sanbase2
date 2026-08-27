defmodule SanbaseWeb.Graphql.ApiMetricCatalogTest do
  # The directory is cached in a `:persistent_term`, which is shared by all the
  # tests, so this test cannot run concurrently with others.
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric.Catalog.Directory
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.MetricGroup

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, market} = MetricCategory.create(%{name: "Market", display_order: 1})
    {:ok, social} = MetricCategory.create(%{name: "Social", display_order: 2})

    {:ok, prices} =
      MetricGroup.create(%{name: "Prices", category_id: market.id, display_order: 1})

    {:ok, _} =
      MetricCategoryMapping.create(%{
        module: "Sanbase.Price.MetricAdapter",
        metric: "price_usd",
        category_id: market.id,
        group_id: prices.id
      })

    {:ok, _} =
      MetricCategoryMapping.create(%{
        module: "Sanbase.Price.MetricAdapter",
        metric: "marketcap_usd",
        category_id: market.id
      })

    Directory.expire_cache!()
    on_exit(&Directory.expire_cache!/0)

    %{conn: conn, market: market, social: social}
  end

  test "the catalog lists metrics with their metadata and category", context do
    result = get_metric_catalog(context.conn, "searchTerm: \"price_usd\"")

    metric = Enum.find(result["metrics"], &(&1["metric"] == "price_usd"))

    assert result["totalCount"] == length(result["metrics"])
    assert metric["categoryName"] == "Market"
    assert metric["groupName"] == "Prices"
    assert metric["isDeprecated"] == false
    assert is_binary(metric["humanReadableName"])
    assert is_binary(metric["minInterval"])
  end

  test "an uncategorized metric is listed without a category", context do
    result = get_metric_catalog(context.conn, "searchTerm: \"daily_active_addresses\"")

    metric =
      result["metrics"]
      |> Enum.find(&(&1["metric"] == "daily_active_addresses"))

    assert metric["categoryName"] == nil
  end

  test "searchTerm matches the human readable name as well", context do
    %{"metrics" => metrics} = get_metric_catalog(context.conn, "searchTerm: \"marketcap\"")

    assert Enum.any?(metrics, &(&1["metric"] == "marketcap_usd"))
  end

  test "filtering by category keeps only the metrics in it", context do
    %{"totalCount" => total_count, "metrics" => metrics} =
      get_metric_catalog(context.conn, "categories: [\"Market\"]")

    assert total_count == 2
    assert Enum.sort(Enum.map(metrics, & &1["metric"])) == ["marketcap_usd", "price_usd"]
  end

  test "filtering by group keeps only the metrics in it", context do
    %{"totalCount" => total_count, "metrics" => metrics} =
      get_metric_catalog(context.conn, "groups: [\"Prices\"]")

    assert total_count == 1
    assert Enum.map(metrics, & &1["metric"]) == ["price_usd"]
  end

  test "totalCount counts all the matches, not just the returned page", context do
    %{"totalCount" => total_count, "metrics" => metrics} =
      get_metric_catalog(context.conn, "pageSize: 5")

    assert length(metrics) == 5
    assert total_count > 5

    %{"metrics" => second_page} =
      get_metric_catalog(context.conn, "page: 2, pageSize: 5")

    assert length(second_page) == 5
    assert MapSet.disjoint?(MapSet.new(metrics), MapSet.new(second_page))
  end

  test "a registry-backed mapping categorizes every metric the record resolves to", context do
    template =
      Sanbase.Metric.Registry.all()
      |> Enum.find(&(&1.is_template and length(&1.parameters) > 1))

    {:ok, _} =
      MetricCategoryMapping.create(%{
        metric_registry_id: template.id,
        category_id: context.social.id
      })

    Directory.expire_cache!()

    resolved_metrics =
      [template]
      |> Sanbase.Metric.Registry.resolve()
      |> Enum.map(& &1.metric)
      |> Enum.filter(&(&1 in Sanbase.Metric.available_metrics()))

    %{"totalCount" => total_count, "metrics" => metrics} =
      get_metric_catalog(context.conn, "categories: [\"Social\"], pageSize: 500")

    assert total_count == length(resolved_metrics)

    assert Enum.all?(metrics, &(&1["categoryName"] == "Social"))
    assert Enum.sort(Enum.map(metrics, & &1["metric"])) == Enum.sort(resolved_metrics)
  end

  test "the categories carry the number of metrics in them", context do
    categories = get_metric_catalog_categories(context.conn)

    market = Enum.find(categories, &(&1["name"] == "Market"))
    social = Enum.find(categories, &(&1["name"] == "Social"))

    assert market["metricsCount"] == 2
    assert market["groups"] == [%{"name" => "Prices", "metricsCount" => 1}]

    assert social["metricsCount"] == 0
    assert social["groups"] == []
  end

  defp get_metric_catalog(conn, args) do
    query = """
    {
      getMetricCatalog(#{args}) {
        totalCount
        metrics {
          metric
          humanReadableName
          categoryName
          groupName
          minInterval
          isDeprecated
          docs { link }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMetricCatalog"])
  end

  defp get_metric_catalog_categories(conn) do
    query = """
    {
      getMetricCatalogCategories {
        name
        metricsCount
        groups { name metricsCount }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMetricCatalogCategories"])
  end
end
