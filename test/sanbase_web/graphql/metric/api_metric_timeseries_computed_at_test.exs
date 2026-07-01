defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesComputedAtTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @metric "daily_active_addresses"

  # `computed_at` is ALWAYS selected in the generated ClickHouse SQL (so the rows
  # returned by ClickHouse always carry it as the last column). Whether it is
  # exposed is decided at the API layer:
  #   * typed fields  -> returned only when the client selects `computedAt`
  #   * *Json fields  -> returned only when named in the `fields` argument

  setup do
    %{user: user} =
      insert(:subscription_pro_sanbase, user: insert(:user, metric_access_level: "alpha"))

    project1 = insert(:random_project, slug: "aaaaa")
    project2 = insert(:random_project, slug: "bbbbb")
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      project1: project1,
      project2: project2,
      slug: project1.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z],
      interval: "1d"
    ]
  end

  describe "timeseriesData" do
    test "exposes computedAt when the field is selected", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      dt2 = ~U[2019-01-02 00:00:00Z]
      computed_at1 = ~U[2019-01-05 00:00:00Z]
      computed_at2 = ~U[2019-01-06 00:00:00Z]

      rows = [
        [DateTime.to_unix(dt1), 100.0, DateTime.to_unix(computed_at1)],
        [DateTime.to_unix(dt2), 200.0, DateTime.to_unix(computed_at2)]
      ]

      query = """
      {
        getMetric(metric: "#{@metric}", storeExecutedClickhouseSql: true){
          timeseriesData(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
            datetime
            value
            computedAt
          }
          executedClickhouseSql
        }
      }
      """

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        %{"data" => %{"getMetric" => metric_data}} =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)

        assert metric_data["timeseriesData"] == [
                 %{
                   "datetime" => "2019-01-01T00:00:00Z",
                   "value" => 100.0,
                   "computedAt" => "2019-01-05T00:00:00Z"
                 },
                 %{
                   "datetime" => "2019-01-02T00:00:00Z",
                   "value" => 200.0,
                   "computedAt" => "2019-01-06T00:00:00Z"
                 }
               ]

        assert Enum.join(metric_data["executedClickhouseSql"], "\n") =~ "AS computed_at"
      end)
    end

    test "omits computedAt from the response when not selected, though the SQL still selects it",
         context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      dt2 = ~U[2019-01-02 00:00:00Z]
      computed_at1 = ~U[2019-01-05 00:00:00Z]
      computed_at2 = ~U[2019-01-06 00:00:00Z]

      # computed_at is always fetched, so ClickHouse returns the extra column
      rows = [
        [DateTime.to_unix(dt1), 100.0, DateTime.to_unix(computed_at1)],
        [DateTime.to_unix(dt2), 200.0, DateTime.to_unix(computed_at2)]
      ]

      query = """
      {
        getMetric(metric: "#{@metric}", storeExecutedClickhouseSql: true){
          timeseriesData(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
            datetime
            value
          }
          executedClickhouseSql
        }
      }
      """

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        %{"data" => %{"getMetric" => metric_data}} =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)

        # GraphQL field selection filters computedAt out of the typed response.
        assert metric_data["timeseriesData"] == [
                 %{"datetime" => "2019-01-01T00:00:00Z", "value" => 100.0},
                 %{"datetime" => "2019-01-02T00:00:00Z", "value" => 200.0}
               ]

        # ...but it is still always part of the query.
        assert Enum.join(metric_data["executedClickhouseSql"], "\n") =~ "AS computed_at"
      end)
    end
  end

  describe "timeseriesDataJson" do
    test "does not leak computedAt when fields are not given", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at1 = ~U[2019-01-05 00:00:00Z]
      rows = [[DateTime.to_unix(dt1), 100.0, DateTime.to_unix(computed_at1)]]

      query = json_query(slug, from, to, interval, nil)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataJson"])

        assert result == [%{"datetime" => "2019-01-01T00:00:00Z", "value" => 100.0}]
      end)
    end

    test "includes computedAt when named in the fields argument", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at1 = ~U[2019-01-05 00:00:00Z]
      rows = [[DateTime.to_unix(dt1), 100.0, DateTime.to_unix(computed_at1)]]

      query =
        json_query(slug, from, to, interval, ~s|{datetime: "d", value: "v", computedAt: "c"}|)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataJson"])

        assert result == [
                 %{"d" => "2019-01-01T00:00:00Z", "v" => 100.0, "c" => "2019-01-05T00:00:00Z"}
               ]
      end)
    end
  end

  describe "timeseriesDataPerSlug" do
    test "exposes computedAt inside each data element when selected", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at = ~U[2019-01-05 00:00:00Z]

      rows = [
        [DateTime.to_unix(dt1), p1.slug, 400.0, DateTime.to_unix(computed_at)],
        [DateTime.to_unix(dt1), p2.slug, 100.0, DateTime.to_unix(computed_at)]
      ]

      query = """
        {
          getMetric(metric: "#{@metric}", storeExecutedClickhouseSql: true){
            timeseriesDataPerSlug(
              selector: {slugs: ["#{p1.slug}", "#{p2.slug}"]},
              from: "#{from}", to: "#{to}", interval: "1d"){
                datetime
                data{ slug value computedAt }
              }
            executedClickhouseSql
          }
        }
      """

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        %{"data" => %{"getMetric" => metric_data}} =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)

        assert %{"datetime" => dt_str, "data" => data} =
                 metric_data["timeseriesDataPerSlug"] |> Enum.at(0)

        assert dt_str |> Sanbase.Utils.DateTime.from_iso8601!() == dt1

        assert %{"slug" => p1.slug, "value" => 400.0, "computedAt" => "2019-01-05T00:00:00Z"} in data

        assert %{"slug" => p2.slug, "value" => 100.0, "computedAt" => "2019-01-05T00:00:00Z"} in data

        assert Enum.join(metric_data["executedClickhouseSql"], "\n") =~ "AS computed_at"
      end)
    end
  end

  describe "timeseriesDataPerSlugJson" do
    test "does not leak computedAt when fields are not given", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at = ~U[2019-01-05 00:00:00Z]
      rows = [[DateTime.to_unix(dt1), p1.slug, 400, DateTime.to_unix(computed_at)]]

      query = per_slug_json_query(p1, p2, from, to, nil)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataPerSlugJson"])

        assert %{"data" => data} = result |> Enum.at(0)
        assert %{"slug" => p1.slug, "value" => 400} in data
        refute Enum.any?(data, &Map.has_key?(&1, "computedAt"))
      end)
    end

    test "includes computedAt when named in the fields argument", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at = ~U[2019-01-05 00:00:00Z]
      rows = [[DateTime.to_unix(dt1), p1.slug, 400, DateTime.to_unix(computed_at)]]

      query =
        per_slug_json_query(
          p1,
          p2,
          from,
          to,
          ~s|{data: "d", slug: "s", value: "v", computedAt: "c"}|
        )

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataPerSlugJson"])

        assert %{"d" => data} = result |> Enum.at(0)
        assert %{"s" => p1.slug, "v" => 400, "c" => "2019-01-05T00:00:00Z"} in data
      end)
    end
  end

  defp json_query(slug, from, to, interval, fields) do
    """
    {
      getMetric(metric: "#{@metric}"){
        timeseriesDataJson(
          slug: "#{slug}"
          from: "#{from}"
          to: "#{to}"
          interval: "#{interval}"
          #{if fields, do: "fields: #{fields}"}
        )
      }
    }
    """
  end

  defp per_slug_json_query(p1, p2, from, to, fields) do
    """
    {
      getMetric(metric: "#{@metric}"){
        timeseriesDataPerSlugJson(
          selector: {slugs: ["#{p1.slug}", "#{p2.slug}"]},
          from: "#{from}", to: "#{to}", interval: "1d"
          #{if fields, do: "fields: #{fields}"})
      }
    }
    """
  end
end
