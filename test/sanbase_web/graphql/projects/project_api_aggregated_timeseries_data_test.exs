defmodule SanbaseWeb.Graphql.ProjectApiAggregatedTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Clickhouse.MetricAdapter

  setup do
    %{
      p1: insert(:random_erc20_project),
      p2: insert(:random_erc20_project),
      p3: insert(:random_erc20_project),
      p4: insert(:random_erc20_project),
      p5: insert(:random_project)
    }
  end

  test "fetch aggregated timeseries data projects", context do
    slugs = Enum.map([context.p1, context.p2, context.p3, context.p4, context.p5], & &1.slug)

    MetricAdapter
    |> Sanbase.Mock.prepare_mock(
      :aggregated_timeseries_data,
      fn _, %{slug: slugs}, _, _, _ ->
        result = Map.new(slugs, fn slug -> {slug, :rand.uniform(100)} end)
        {:ok, result}
      end
    )
    |> Sanbase.Mock.prepare_mock2(
      &MetricAdapter.available_slugs/1,
      {:ok, slugs}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        context.conn
        |> execute(
          "dev_activity_1d",
          ~U[2020-01-01 00:00:00Z],
          ~U[2020-02-01 00:00:00Z],
          :avg
        )
        |> get_in(["data", "allProjects"])

      assert length(result) == 5
      Enum.each(result, &match?(%{"aggregatedTimeseriesData" => _, "slug" => _}, &1))
    end)
  end

  defp execute(conn, metric, from, to, aggregation) do
    query = """
    {
      allProjects {
        aggregatedTimeseriesData(
          metric: "#{metric}"
          from: "#{from}"
          to: "#{to}"
          aggregation: #{aggregation |> Atom.to_string() |> String.upcase()})
        slug
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
