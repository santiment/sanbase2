defmodule SanbaseWeb.Graphql.ApiMetricComputedAtTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric

  setup do
    project = insert(:random_erc20_project)
    %{project: project}
  end

  test "returns last datetime computed at for all available metric", context do
    %{conn: conn, project: project} = context

    metrics = Enum.shuffle(Metric.available_metrics())
    datetime = ~U[2020-01-01 12:45:40Z]
    clickhouse_response = {:ok, %{rows: [[DateTime.to_unix(datetime)]]}}

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2(clickhouse_response)
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Twitter.MetricAdapter.last_datetime_computed_at/2,
      {:ok, datetime}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      for metric <- metrics do
        %{"data" => %{"getMetric" => %{"lastDatetimeComputedAt" => last_dt}}} =
          get_last_datetime_computed_at(conn, metric, %{slug: project.slug})

        last_dt = Sanbase.DateTimeUtils.from_iso8601!(last_dt)
        assert match?(%DateTime{}, last_dt)
      end
    end)
  end

  test "returns error for unavailable metric", context do
    %{conn: conn, project: project} = context
    rand_metrics = Enum.map(1..10, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_metrics()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_last_datetime_computed_at(conn, metric, %{slug: project.slug})

      assert error_message ==
               "The metric '#{metric}' is not supported, is deprecated or is mistyped."
    end
  end

  defp get_last_datetime_computed_at(conn, metric, selector) do
    selector = extend_selector_with_required_fields(metric, selector)

    query = """
    {
      getMetric(metric: "#{metric}"){
        lastDatetimeComputedAt(selector: #{map_to_input_object_str(selector)})
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
