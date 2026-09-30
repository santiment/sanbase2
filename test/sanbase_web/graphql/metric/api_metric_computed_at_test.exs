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

    metrics = Metric.available_metrics() |> Enum.shuffle()
    datetime = ~U[2020-01-01 12:45:40Z]
    clickhouse_response = {:ok, %{rows: [[datetime |> DateTime.to_unix()]]}}

    Sanbase.Mock.prepare_mock2(
      &Sanbase.ClickhouseRepo.query/3,
      clickhouse_response
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Twitter.MetricAdapter.last_datetime_computed_at/3,
      {:ok, datetime}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      for metric <- metrics do
        %{"data" => %{"getMetric" => %{"lastDatetimeComputedAt" => last_dt}}} =
          get_last_datetime_computed_at(conn, metric, %{slug: project.slug})

        last_dt = Sanbase.Utils.DateTime.from_iso8601!(last_dt)
        assert match?(%DateTime{}, last_dt)
      end
    end)
  end

  test "passes the requested version to the adapter", context do
    %{project: project} = context
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)
    test_pid = self()

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :last_datetime_computed_at,
      fn _metric, _selector, opts ->
        send(test_pid, {:adapter_version, Keyword.get(opts, :version)})
        {:ok, ~U[2020-01-01 12:45:40Z]}
      end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      for {version, expected} <- [{nil, "1.0"}, {"2.1", "2.1"}] do
        SanbaseWeb.Graphql.Cache.clear_all()

        assert %{"data" => %{"getMetric" => %{"lastDatetimeComputedAt" => _}}} =
                 get_last_datetime_computed_at(
                   conn,
                   "daily_active_addresses",
                   %{slug: project.slug},
                   version
                 )

        assert_receive {:adapter_version, ^expected}
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

  defp get_last_datetime_computed_at(conn, metric, selector, version \\ nil) do
    selector = extend_selector_with_required_fields(metric, selector)
    version_arg = if version, do: ~s|, version: "#{version}"|, else: ""

    query = """
    {
      getMetric(metric: "#{metric}"#{version_arg}){
        lastDatetimeComputedAt(selector: #{map_to_input_object_str(selector)})
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
