defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesComputedAtTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @metric "daily_active_addresses"

  # `computed_at` is always selected in the generated ClickHouse SQL, but it is
  # exposed ONLY through the `*Json` fields, and only when `includeComputedAt: true`
  # is passed. The deprecated typed fields (`timeseriesData` /
  # `timeseriesDataPerSlug`) do not expose it at all. `fields` only renames keys.

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

  describe "timeseriesDataJson" do
    test "defaults to datetime + value", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
      rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-05 00:00:00Z])]

      result =
        run_json(conn, json_query(slug, from, to, interval, []), rows, "timeseriesDataJson")

      assert result == [%{"datetime" => "2019-01-01T00:00:00Z", "value" => 100.0}]
    end

    test "fields only renames keys - unnamed fields keep their default key", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
      rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-05 00:00:00Z])]

      query = json_query(slug, from, to, interval, fields: ~s|{datetime: "d"}|)
      result = run_json(conn, query, rows, "timeseriesDataJson")

      # value is still present under its default key - fields renames, not selects
      assert result == [%{"d" => "2019-01-01T00:00:00Z", "value" => 100.0}]
    end

    test "includeComputedAt appends computedAt", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
      rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-05 00:00:00Z])]

      query = json_query(slug, from, to, interval, include_computed_at: true)
      result = run_json(conn, query, rows, "timeseriesDataJson")

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "value" => 100.0,
                 "computedAt" => "2019-01-05T00:00:00Z"
               }
             ]
    end

    test "includeComputedAt composes with fields renaming", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
      rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-05 00:00:00Z])]

      query =
        json_query(slug, from, to, interval,
          fields: ~s|{datetime: "d"}|,
          include_computed_at: true
        )

      result = run_json(conn, query, rows, "timeseriesDataJson")

      assert result == [
               %{
                 "d" => "2019-01-01T00:00:00Z",
                 "value" => 100.0,
                 "computedAt" => "2019-01-05T00:00:00Z"
               }
             ]
    end

    test "includeComputedAt renames computedAt when it is named in fields", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
      rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-05 00:00:00Z])]

      query =
        json_query(slug, from, to, interval,
          fields: ~s|{datetime: "d", value: "v", computedAt: "c"}|,
          include_computed_at: true
        )

      result = run_json(conn, query, rows, "timeseriesDataJson")

      assert result == [
               %{"d" => "2019-01-01T00:00:00Z", "v" => 100.0, "c" => "2019-01-05T00:00:00Z"}
             ]
    end

    test "naming computedAt in fields without includeComputedAt returns an error", context do
      %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
      rows = [row(~U[2019-01-01 00:00:00Z], 100.0, ~U[2019-01-05 00:00:00Z])]

      query = json_query(slug, from, to, interval, fields: ~s|{datetime: "d", computedAt: "c"}|)

      error_msg =
        Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
        |> Sanbase.Mock.run_with_mocks(fn ->
          conn
          |> post("/graphql", query_skeleton(query, "getMetric"))
          |> json_response(200)
          |> get_in(["errors", Access.at(0), "message"])
        end)

      assert error_msg =~ "includeComputedAt"
    end
  end

  describe "timeseriesDataPerSlugJson" do
    test "does not include computedAt by default", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context
      rows = [per_slug_row(~U[2019-01-01 00:00:00Z], p1.slug, 400, ~U[2019-01-05 00:00:00Z])]

      query = per_slug_json_query(p1, p2, from, to, [])
      result = run_json(conn, query, rows, "timeseriesDataPerSlugJson")

      assert %{"data" => data} = result |> Enum.at(0)
      assert %{"slug" => p1.slug, "value" => 400} in data
      refute Enum.any?(data, &Map.has_key?(&1, "computedAt"))
    end

    test "includeComputedAt appends computedAt inside each data element", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context
      rows = [per_slug_row(~U[2019-01-01 00:00:00Z], p1.slug, 400, ~U[2019-01-05 00:00:00Z])]

      query = per_slug_json_query(p1, p2, from, to, include_computed_at: true)
      result = run_json(conn, query, rows, "timeseriesDataPerSlugJson")

      assert %{"data" => data} = result |> Enum.at(0)
      assert %{"slug" => p1.slug, "value" => 400, "computedAt" => "2019-01-05T00:00:00Z"} in data
    end

    test "renames inner fields and still returns data even when `data` is not named", context do
      %{conn: conn, from: from, to: to, project1: p1, project2: p2} = context
      rows = [per_slug_row(~U[2019-01-01 00:00:00Z], p1.slug, 400, ~U[2019-01-05 00:00:00Z])]

      # names datetime/slug/value/computedAt but NOT `data` - since fields only
      # renames (never drops), `data` still appears under its default key
      query =
        per_slug_json_query(p1, p2, from, to,
          fields: ~s|{datetime: "d", slug: "s", value: "v", computedAt: "ca"}|,
          include_computed_at: true
        )

      result = run_json(conn, query, rows, "timeseriesDataPerSlugJson")

      assert %{"d" => _dt, "data" => data} = result |> Enum.at(0)
      assert %{"s" => p1.slug, "v" => 400, "ca" => "2019-01-05T00:00:00Z"} in data
    end
  end

  defp row(dt, value, computed_at),
    do: [DateTime.to_unix(dt), value, DateTime.to_unix(computed_at)]

  defp per_slug_row(dt, slug, value, computed_at),
    do: [DateTime.to_unix(dt), slug, value, DateTime.to_unix(computed_at)]

  defp run_json(conn, query, rows, key) do
    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      conn
      |> post("/graphql", query_skeleton(query, "getMetric"))
      |> json_response(200)
      |> get_in(["data", "getMetric", key])
    end)
  end

  defp json_query(slug, from, to, interval, opts) do
    fields = Keyword.get(opts, :fields)
    include_computed_at? = Keyword.get(opts, :include_computed_at, false)

    """
    {
      getMetric(metric: "#{@metric}"){
        timeseriesDataJson(
          slug: "#{slug}"
          from: "#{from}"
          to: "#{to}"
          interval: "#{interval}"
          #{if fields, do: "fields: #{fields}"}
          includeComputedAt: #{include_computed_at?}
        )
      }
    }
    """
  end

  defp per_slug_json_query(p1, p2, from, to, opts) do
    fields = Keyword.get(opts, :fields)
    include_computed_at? = Keyword.get(opts, :include_computed_at, false)

    """
    {
      getMetric(metric: "#{@metric}"){
        timeseriesDataPerSlugJson(
          selector: {slugs: ["#{p1.slug}", "#{p2.slug}"]},
          from: "#{from}", to: "#{to}", interval: "1d"
          #{if fields, do: "fields: #{fields}"}
          includeComputedAt: #{include_computed_at?})
      }
    }
    """
  end
end
