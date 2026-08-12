defmodule SanbaseWeb.Graphql.DataFetchErrorsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{
      p1: insert(:random_erc20_project),
      p2: insert(:random_erc20_project),
      p3: insert(:random_erc20_project)
    }
  end

  test "failed batch fetch degrades the field and is reported in extensions", context do
    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      fn _, _, _, _, _ -> {:error, "Something went wrong"} end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      response = execute(context.conn, "dev_activity_1d")

      # The request as a whole succeeds - no hard GraphQL errors
      refute Map.has_key?(response, "errors")

      # The field degrades to nil for every project instead of failing the request
      projects = get_in(response, ["data", "allProjects"])
      assert length(projects) == 3

      Enum.each(projects, fn project ->
        assert %{"aggregatedTimeseriesData" => nil, "slug" => _} = project
      end)

      # The failure is communicated via the soft-error channel
      data_fetch_errors = get_in(response, ["extensions", "dataFetchErrors"])
      assert is_list(data_fetch_errors)
      assert [%{"source" => "aggregated_metric", "reason" => reason}] = data_fetch_errors
      assert reason =~ "Something went wrong"
    end)
  end

  test "successful batch fetch does not add dataFetchErrors to extensions", context do
    slugs = [context.p1, context.p2, context.p3] |> Enum.map(& &1.slug)

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      fn _, %{slug: slugs}, _, _, _ ->
        {:ok, Map.new(slugs, fn slug -> {slug, 10} end)}
      end
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Clickhouse.MetricAdapter.available_slugs/2,
      {:ok, slugs}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      response = execute(context.conn, "dev_activity_1d")

      refute Map.has_key?(response, "errors")

      projects = get_in(response, ["data", "allProjects"])
      assert length(projects) == 3

      Enum.each(projects, fn project ->
        assert %{"aggregatedTimeseriesData" => 10.0, "slug" => _} = project
      end)

      assert get_in(response, ["extensions", "dataFetchErrors"]) == nil
    end)
  end

  defp execute(conn, metric) do
    query = """
    {
      allProjects {
        aggregatedTimeseriesData(
          metric: "#{metric}"
          from: "2020-01-01T00:00:00Z"
          to: "2020-02-01T00:00:00Z"
          aggregation: AVG)
        slug
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
