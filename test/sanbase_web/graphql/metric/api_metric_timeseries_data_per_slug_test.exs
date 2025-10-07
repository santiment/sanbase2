defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesDataPerSlugTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

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
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z]
    ]
  end

  test "price_usd when the source is cryptocompare", context do
    # Test that when the source is cryptocompare the prices are served from the
    # PricePair module instead of the Price module
    %{conn: conn, from: from, to: to, project1: project1, project2: project2} = context

    dt1 = ~U[2020-10-10 00:00:00Z]
    dt2 = ~U[2020-10-11 00:00:00Z]

    rows = [
      [DateTime.to_unix(dt1), project1.slug, 200],
      [DateTime.to_unix(dt1), project2.slug, 150],
      [DateTime.to_unix(dt2), project1.slug, 400],
      [DateTime.to_unix(dt2), project2.slug, 100]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_timeseries_per_slug_metric(
          conn,
          "price_usd",
          %{slugs: [project1.slug, project2.slug], source: "cryptocompare"},
          from,
          to,
          "1d",
          :last
        )
        |> extract_timeseries_data_per_slug()

      assert %{"datetime" => dt_str1, "data" => data1} = result |> Enum.at(0)
      assert dt_str1 |> Sanbase.DateTimeUtils.from_iso8601!() == dt1
      assert %{"slug" => project1.slug, "value" => 200.0} in data1
      assert %{"slug" => project2.slug, "value" => 150.0} in data1

      assert %{"datetime" => dt_str2, "data" => data2} = result |> Enum.at(1)
      assert dt_str2 |> Sanbase.DateTimeUtils.from_iso8601!() == dt2
      assert %{"slug" => project1.slug, "value" => 400.0} in data2
      assert %{"slug" => project2.slug, "value" => 100.0} in data2
    end)
  end

  test "returns data - timeseriesDataPerSlug", context do
    %{conn: conn, from: from, to: to, project1: project1, project2: project2} = context

    dt1 = ~U[2020-10-10 00:00:00Z]
    dt2 = ~U[2020-10-11 00:00:00Z]

    rows = [
      [DateTime.to_unix(dt1), project1.slug, 400],
      [DateTime.to_unix(dt1), project2.slug, 100],
      [DateTime.to_unix(dt2), project1.slug, 500],
      [DateTime.to_unix(dt2), project2.slug, 200]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_timeseries_per_slug_metric(
          conn,
          "daily_active_addresses",
          %{slugs: [project1.slug, project2.slug]},
          from,
          to,
          "1d",
          :avg
        )
        |> extract_timeseries_data_per_slug()

      assert %{"datetime" => dt_str1, "data" => data1} = result |> Enum.at(0)
      assert dt_str1 |> Sanbase.DateTimeUtils.from_iso8601!() == dt1
      assert %{"slug" => project1.slug, "value" => 400.0} in data1
      assert %{"slug" => project2.slug, "value" => 100.0} in data1

      assert %{"datetime" => dt_str2, "data" => data2} = result |> Enum.at(1)
      assert dt_str2 |> Sanbase.DateTimeUtils.from_iso8601!() == dt2
      assert %{"slug" => project1.slug, "value" => 500.0} in data2
      assert %{"slug" => project2.slug, "value" => 200.0} in data2
    end)
  end

  test "returns data - timeseriesDataPerSlugJson", context do
    %{conn: conn, from: from, to: to, project1: project1, project2: project2} = context

    dt1 = ~U[2020-10-10 00:00:00Z]
    dt2 = ~U[2020-10-11 00:00:00Z]

    rows = [
      [DateTime.to_unix(dt1), project1.slug, 400],
      [DateTime.to_unix(dt1), project2.slug, 100],
      [DateTime.to_unix(dt2), project1.slug, 500],
      [DateTime.to_unix(dt2), project2.slug, 200]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      # Without fields renaming
      result =
        get_timeseries_per_slug_json_metric(
          conn,
          "daily_active_addresses",
          %{slugs: [project1.slug, project2.slug]},
          from,
          to,
          "1d",
          :avg,
          nil
        )
        |> get_in(["data", "getMetric", "timeseriesDataPerSlugJson"])

      assert %{"datetime" => dt_str1, "data" => data1} = result |> Enum.at(0)
      assert dt_str1 |> Sanbase.DateTimeUtils.from_iso8601!() == dt1
      assert %{"slug" => project1.slug, "value" => 400} in data1
      assert %{"slug" => project2.slug, "value" => 100} in data1

      assert %{"datetime" => dt_str2, "data" => data2} = result |> Enum.at(1)
      assert dt_str2 |> Sanbase.DateTimeUtils.from_iso8601!() == dt2
      assert %{"slug" => project1.slug, "value" => 500} in data2
      assert %{"slug" => project2.slug, "value" => 200} in data2

      # With fields renaming
      result =
        get_timeseries_per_slug_json_metric(
          conn,
          "daily_active_addresses",
          %{slugs: [project1.slug, project2.slug]},
          from,
          to,
          "1d",
          :avg,
          "{datetime: \"dt\", data: \"d\", value: \"v\", slug: \"s\"}"
        )
        |> get_in(["data", "getMetric", "timeseriesDataPerSlugJson"])

      assert %{"dt" => dt_str1, "d" => data1} = result |> Enum.at(0)
      assert dt_str1 |> Sanbase.DateTimeUtils.from_iso8601!() == dt1
      assert %{"s" => project1.slug, "v" => 400} in data1
      assert %{"s" => project2.slug, "v" => 100} in data1

      assert %{"dt" => dt_str2, "d" => data2} = result |> Enum.at(1)
      assert dt_str2 |> Sanbase.DateTimeUtils.from_iso8601!() == dt2
      assert %{"s" => project1.slug, "v" => 500} in data2
      assert %{"s" => project2.slug, "v" => 200} in data2
    end)
  end

  # The graphql error is logged
  @tag capture_log: true
  test "unsupported slug in list returns error", context do
    %{conn: conn, from: from, to: to, project1: project1, project2: project2} = context

    result =
      get_timeseries_per_slug_metric(
        conn,
        "daily_active_addresses",
        %{slugs: [project1.slug, project2.slug, "unsupported_slug"]},
        from,
        to,
        "1d",
        :avg
      )

    error_msg = result["errors"] |> hd() |> Map.get("message")

    assert error_msg =~
             "Can't fetch daily_active_addresses for project with slug [\"aaaaa\", \"bbbbb\", \"unsupported_slug\"], Reason: \"The slug \\\"unsupported_slug\\\" is not an existing slug."
  end

  # Private functions

  defp get_timeseries_per_slug_metric(
         conn,
         metric,
         selector,
         from,
         to,
         interval,
         aggregation
       ) do
    query = get_timeseries_per_slug_query(metric, selector, from, to, interval, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp get_timeseries_per_slug_json_metric(
         conn,
         metric,
         selector,
         from,
         to,
         interval,
         aggregation,
         fields
       ) do
    query =
      get_timeseries_per_slug_json_query(
        metric,
        selector,
        from,
        to,
        interval,
        aggregation,
        fields
      )

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  def extract_timeseries_data_per_slug(result) do
    %{"data" => %{"getMetric" => %{"timeseriesDataPerSlug" => timeseries_data}}} = result

    timeseries_data
  end

  defp get_timeseries_per_slug_query(metric, selector, from, to, interval, aggregation) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesDataPerSlug(
            selector: #{map_to_input_object_str(selector)},
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}",
            aggregation: #{Atom.to_string(aggregation) |> String.upcase()}){
              datetime
              data{ slug value }
            }
        }
      }
    """
  end

  defp get_timeseries_per_slug_json_query(
         metric,
         selector,
         from,
         to,
         interval,
         aggregation,
         fields
       ) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesDataPerSlugJson(
            selector: #{map_to_input_object_str(selector)},
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}",
            aggregation: #{Atom.to_string(aggregation) |> String.upcase()}
            #{if fields, do: "fields: #{fields}"})
        }
      }
    """
  end
end
