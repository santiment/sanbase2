defmodule SanbaseWeb.Graphql.ProjectApiOrderingTest do
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

  test "order by metric", context do
    %{conn: conn, from: from, to: to} = context

    order_by = %{
      metric: "price_usd",
      from: from,
      to: to,
      direction: :asc
    }

    %{p1: p1, p2: p2, p3: p3, p4: p4, p5: p5} = context

    (&Sanbase.Price.MetricAdapter.slugs_order/5)
    |> Sanbase.Mock.prepare_mock2({:ok, [p1.slug, p2.slug, p3.slug, p4.slug, p5.slug]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      slugs =
        conn
        |> get_projects(order_by)
        |> get_in(["data", "allProjects"])
        |> Enum.map(& &1["slug"])

      assert slugs == [p1.slug, p2.slug, p3.slug, p4.slug, p5.slug]
    end)
  end

  test "order by with pagination", context do
    %{conn: conn, from: from, to: to} = context

    order_by = %{
      metric: "daily_active_addresses",
      from: from,
      to: to,
      direction: :desc
    }

    pagination = %{
      page: 2,
      page_size: 2
    }

    %{p1: p1, p2: p2, p3: p3, p4: p4, p5: p5} = context

    (&Sanbase.Clickhouse.MetricAdapter.slugs_order/5)
    |> Sanbase.Mock.prepare_mock2({:ok, [p1.slug, p2.slug, p3.slug, p4.slug, p5.slug]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      slugs =
        conn
        |> get_projects(order_by, pagination)
        |> get_in(["data", "allProjects"])
        |> Enum.map(& &1["slug"])

      assert slugs == [p3.slug, p4.slug]
    end)
  end

  defp get_projects(conn, order_by, pagination \\ nil) do
    order_by_str = "orderBy: " <> map_to_input_object_str(order_by)

    pagination_str =
      case pagination do
        nil -> ""
        %{} -> "pagination: {page: #{pagination.page}, pageSize: #{pagination.page_size} }"
      end

    query = """
    {
      allProjects(selector: {#{order_by_str}, #{pagination_str} }){
        slug
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
