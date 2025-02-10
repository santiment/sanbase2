defmodule SanbaseWeb.Graphql.ProjectApiFiltersTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    [
      p1: insert(:random_project),
      p2: insert(:random_project),
      p3: insert(:random_project),
      p4: insert(:random_project),
      p5: insert(:random_project),
      from: Timex.shift(DateTime.utc_now(), days: -30),
      to: DateTime.utc_now()
    ]
  end

  test "one filter", context do
    %{conn: conn, from: from, to: to} = context

    filter = %{
      metric: "daily_active_addresses",
      from: from,
      to: to,
      aggregation: :last,
      operator: :greater_than,
      threshold: 10
    }

    %{p1: p1, p2: p2, p3: p3, p4: p4, p5: p5} = context

    (&Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6)
    |> Sanbase.Mock.prepare_mock2({:ok, [p1.slug, p2.slug]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      slugs =
        conn
        |> filtered_projects([filter])
        |> get_in(["data", "allProjects"])
        |> Enum.map(& &1["slug"])

      assert p1.slug in slugs
      assert p2.slug in slugs

      refute p3.slug in slugs
      refute p4.slug in slugs
      refute p5.slug in slugs
    end)
  end

  test "multiple filters", context do
    %{conn: conn, from: from, to: to} = context

    filter1 = %{
      metric: "volume_usd",
      from: from,
      to: to,
      aggregation: :last,
      operator: :greater_than,
      threshold: 10
    }

    filter2 = %{
      metric: "daily_active_addresses",
      from: from,
      to: to,
      aggregation: :last,
      operator: :greater_than_or_equal_to,
      threshold: 100
    }

    %{p1: p1, p2: p2, p3: p3, p4: p4, p5: p5} = context

    (&Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6)
    |> Sanbase.Mock.prepare_mock2({:ok, [p1.slug, p2.slug, p3.slug]})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Price.MetricAdapter.slugs_by_filter/6,
      {:ok, [p2.slug, p3.slug, p4.slug, p5.slug]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      slugs =
        conn
        |> filtered_projects([filter1, filter2])
        |> get_in(["data", "allProjects"])
        |> Enum.map(& &1["slug"])

      assert p2.slug in slugs
      assert p3.slug in slugs

      refute p1.slug in slugs
      refute p4.slug in slugs
      refute p5.slug in slugs
    end)
  end

  defp filtered_projects(conn, filters) do
    filters_str = Enum.map_join(filters, ", ", &map_to_input_object_str/1)

    filters_str = "[" <> filters_str <> "]"

    query = """
    {
      allProjects(selector: {filters: #{filters_str} }){
        slug
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
