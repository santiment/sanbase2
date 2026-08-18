defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesDataWithDuplicatesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @metric "daily_active_addresses"

  # `timeseriesDataJsonWithDuplicates` returns the data as it is stored in
  # Clickhouse - if an asset/metric/dt has multiple values with different
  # computed_at, all of them are returned. computedAt is included by default.

  setup do
    %{user: user} =
      insert(:subscription_pro_sanbase, user: insert(:user, metric_access_level: "alpha"))

    project = insert(:random_project)
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      slug: project.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-03 00:00:00Z]
    ]
  end

  test "returns all values when a datetime has multiple computed_at", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    rows = [
      row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-01 12:00:00Z]),
      row(~U[2019-01-01 00:00:00Z], 120.0, ~U[2019-01-02 12:00:00Z]),
      row(~U[2019-01-02 00:00:00Z], 200.0, ~U[2019-01-02 12:00:00Z])
    ]

    result = run_json(conn, query(slug, from, to, []), rows)

    assert result == [
             %{
               "datetime" => "2019-01-01T00:00:00Z",
               "value" => 100.0,
               "computedAt" => "2019-01-01T12:00:00Z"
             },
             %{
               "datetime" => "2019-01-01T00:00:00Z",
               "value" => 120.0,
               "computedAt" => "2019-01-02T12:00:00Z"
             },
             %{
               "datetime" => "2019-01-02T00:00:00Z",
               "value" => 200.0,
               "computedAt" => "2019-01-02T12:00:00Z"
             }
           ]
  end

  test "includeComputedAt: false returns only datetime and value", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    rows = [
      row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-01 12:00:00Z]),
      row(~U[2019-01-01 00:00:00Z], 120.0, ~U[2019-01-02 12:00:00Z])
    ]

    result = run_json(conn, query(slug, from, to, include_computed_at: false), rows)

    assert result == [
             %{"datetime" => "2019-01-01T00:00:00Z", "value" => 100.0},
             %{"datetime" => "2019-01-01T00:00:00Z", "value" => 120.0}
           ]
  end

  test "fields renames the output keys", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-01 12:00:00Z])]

    query =
      query(slug, from, to, fields: ~s|{datetime: "d", value: "v", computedAt: "c"}|)

    result = run_json(conn, query, rows)

    assert result == [
             %{"d" => "2019-01-01T00:00:00Z", "v" => 100.0, "c" => "2019-01-01T12:00:00Z"}
           ]
  end

  @tag capture_log: true
  test "returns an error for metrics not served by an adapter that supports it", context do
    %{conn: conn, slug: slug, from: from, to: to} = context

    error_msg =
      conn
      |> post("/graphql", query_skeleton(query(slug, from, to, metric: "price_usd"), "getMetric"))
      |> json_response(200)
      |> get_in(["errors", Access.at(0), "message"])

    assert error_msg =~ "does not support fetching timeseries data with duplicates"
  end

  test "Sanbase.Metric returns an error when the adapter lacks the callback", context do
    %{slug: slug, from: from, to: to} = context

    assert {:error, error_msg} =
             Sanbase.Metric.timeseries_data_with_duplicates(
               "price_usd",
               %{slug: slug},
               from,
               to,
               "1d",
               []
             )

    assert error_msg =~
             "The metric price_usd does not support fetching timeseries data with duplicates"
  end

  defp row(dt, value, computed_at),
    do: [DateTime.to_unix(dt), value, DateTime.to_unix(computed_at)]

  defp run_json(conn, query, rows) do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      conn
      |> post("/graphql", query_skeleton(query, "getMetric"))
      |> json_response(200)
      |> get_in(["data", "getMetric", "timeseriesDataJsonWithDuplicates"])
    end)
  end

  defp query(slug, from, to, opts) do
    metric = Keyword.get(opts, :metric, @metric)
    fields = Keyword.get(opts, :fields)
    include_computed_at? = Keyword.get(opts, :include_computed_at, true)

    """
    {
      getMetric(metric: "#{metric}"){
        timeseriesDataJsonWithDuplicates(
          slug: "#{slug}"
          from: "#{from}"
          to: "#{to}"
          #{if fields, do: "fields: #{fields}"}
          includeComputedAt: #{include_computed_at?}
        )
      }
    }
    """
  end
end
