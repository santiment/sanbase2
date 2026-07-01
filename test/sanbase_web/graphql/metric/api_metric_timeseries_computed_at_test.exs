defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesComputedAtTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @metric "daily_active_addresses"

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

      # `computed_at` is the 3rd column - matches the SQL built when the flag is on
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

        # The selection actually drove the SQL to select the computed_at column.
        assert Enum.join(metric_data["executedClickhouseSql"], "\n") =~ "AS computed_at"
      end)
    end

    test "does not select the computed_at column when the field is not requested", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      dt2 = ~U[2019-01-02 00:00:00Z]

      # Only 2 columns - matches the SQL built when the flag is off
      rows = [
        [DateTime.to_unix(dt1), 100.0],
        [DateTime.to_unix(dt2), 200.0]
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

        assert metric_data["timeseriesData"] == [
                 %{"datetime" => "2019-01-01T00:00:00Z", "value" => 100.0},
                 %{"datetime" => "2019-01-02T00:00:00Z", "value" => 200.0}
               ]

        refute Enum.join(metric_data["executedClickhouseSql"], "\n") =~ "AS computed_at"
      end)
    end
  end

  describe "timeseriesDataJson" do
    test "includes computedAt only when named in the fields argument", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at1 = ~U[2019-01-05 00:00:00Z]

      # Opted in: `fields` names computedAt -> flag on -> 3-column rows
      rows_with = [[DateTime.to_unix(dt1), 100.0, DateTime.to_unix(computed_at1)]]

      query_with =
        json_query(slug, from, to, interval, ~s|{datetime: "d", value: "v", computedAt: "c"}|)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows_with}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query_with, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataJson"])

        assert result == [
                 %{"d" => "2019-01-01T00:00:00Z", "v" => 100.0, "c" => "2019-01-05T00:00:00Z"}
               ]
      end)

      # Not opted in: `fields` omits computedAt -> flag off -> 2-column rows, no key leaks
      rows_without = [[DateTime.to_unix(dt1), 100.0]]
      query_without = json_query(slug, from, to, interval, ~s|{datetime: "d", value: "v"}|)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows_without}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query_without, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataJson"])

        assert result == [%{"d" => "2019-01-01T00:00:00Z", "v" => 100.0}]
      end)
    end
  end

  describe "timeseriesDataPerSlug" do
    test "exposes computedAt inside each data element when selected", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at = ~U[2019-01-05 00:00:00Z]

      # `computed_at` is the 4th column - matches the SQL built when the flag is on
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
    test "includes computedAt only when named in the fields argument", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context

      dt1 = ~U[2019-01-01 00:00:00Z]
      computed_at = ~U[2019-01-05 00:00:00Z]

      rows_with = [
        [DateTime.to_unix(dt1), p1.slug, 400, DateTime.to_unix(computed_at)]
      ]

      query_with =
        per_slug_json_query(
          p1,
          p2,
          from,
          to,
          ~s|{data: "d", slug: "s", value: "v", computedAt: "c"}|
        )

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows_with}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query_with, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataPerSlugJson"])

        assert %{"d" => data} = result |> Enum.at(0)
        assert %{"s" => p1.slug, "v" => 400, "c" => "2019-01-05T00:00:00Z"} in data
      end)

      # Not opted in -> flag off -> 3-column rows, no computedAt key
      rows_without = [[DateTime.to_unix(dt1), p1.slug, 400]]

      query_without =
        per_slug_json_query(p1, p2, from, to, ~s|{data: "d", slug: "s", value: "v"}|)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows_without}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> post("/graphql", query_skeleton(query_without, "getMetric"))
          |> json_response(200)
          |> get_in(["data", "getMetric", "timeseriesDataPerSlugJson"])

        assert %{"d" => data} = result |> Enum.at(0)
        assert %{"s" => p1.slug, "v" => 400} in data
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
          fields: #{fields}
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
          fields: #{fields})
      }
    }
    """
  end
end
