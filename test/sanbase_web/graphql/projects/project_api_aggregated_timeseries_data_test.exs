defmodule SanbaseWeb.Graphql.ProjectApiAggregatedTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

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
    slugs = [context.p1, context.p2, context.p3, context.p4, context.p5] |> Enum.map(& &1.slug)

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      fn _, %{slug: slugs}, _, _, _ ->
        result = slugs |> Enum.into(%{}, fn slug -> {slug, :rand.uniform(100)} end)
        {:ok, result}
      end
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.available_slugs/1,
      {:ok, slugs}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        execute(
          context.conn,
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
          aggregation: #{Atom.to_string(aggregation) |> String.upcase()})
        slug
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
