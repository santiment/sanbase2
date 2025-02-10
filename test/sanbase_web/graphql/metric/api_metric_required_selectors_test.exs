defmodule SanbaseWeb.Graphql.ApiMetricRequiredSelectorsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @moduletag capture_log: true

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    project = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: project.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z],
      interval: "1d"
    ]
  end

  test "labelled_historical_balance* metrics", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    metrics = ["labelled_historical_balance", "labelled_historical_balance_changes"]

    for metric <- metrics do
      error_msg =
        conn
        |> get_timeseries_metric(
          metric,
          %{slug: slug},
          from,
          to,
          interval
        )
        |> get_in(["errors", Access.at(0), "message"])

      assert error_msg =~
               "metric '#{metric}' must have at least one of the following fields in the selector: labelFqn, labelFqns"
    end
  end

  test "social_active_users metric", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

    error_msg =
      conn
      |> get_timeseries_metric(
        "social_active_users",
        %{slug: slug},
        from,
        to,
        interval
      )
      |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~
             "metric 'social_active_users' must have at least one of the following fields in the selector: source"
  end

  defp get_timeseries_metric(conn, metric, selector, from, to, interval) do
    query = get_timeseries_query(metric, selector, from, to, interval)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_timeseries_query(metric, selector, from, to, interval) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
            selector: #{map_to_input_object_str(selector)},
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}"){
              datetime
              value
            }
        }
      }
    """
  end
end
