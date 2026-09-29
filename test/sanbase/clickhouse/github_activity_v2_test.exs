defmodule Sanbase.Clickhouse.GithubActivityV2Test do
  use Sanbase.DataCase, async: false

  alias Sanbase.Clickhouse.Github.SqlQuery

  @from ~U[2026-06-08 12:00:00Z]
  @to ~U[2026-06-10 00:00:00Z]

  describe "timeseries queries" do
    test "every actor-repo-day group is capped" do
      query = SqlQuery.dev_activity_v2_query(["Org1", "org2"], @from, @to, "1d")

      assert query.parameters[:organizations] == ["org1", "org2"]
      assert query.parameters[:max_daily_events] == SqlQuery.max_daily_actor_repo_events()

      assert query.sql =~ "cityHash64(owner, repo, cityHash64(actor)) AS group_key"
      assert query.sql =~ "least(1, {{max_daily_events}} / day_events)"
    end

    test "day-aligned intervals compute the day totals without a window function" do
      for interval <- ["1d", "7d", "toStartOfDay", "toStartOfWeek", "toStartOfMonth"] do
        query = SqlQuery.dev_activity_v2_query(["org"], @from, @to, interval)

        refute query.sql =~ "sum(events) OVER", "#{interval} should not use a window function"
        assert query.sql =~ "GROUP BY group_key, day"
      end
    end

    test "intraday intervals compute the day totals with a window function" do
      for interval <- ["1h", "5h", "12h", "toStartOfHour"] do
        query = SqlQuery.dev_activity_v2_query(["org"], @from, @to, interval)

        assert query.sql =~ "sum(events) OVER (PARTITION BY group_key, day) AS day_events",
               "#{interval} should use a window function"
      end
    end

    test "the groups span whole days, not the requested time range" do
      query = SqlQuery.dev_activity_v2_query(["org"], @from, @to, "1h")

      assert query.sql =~ "dt >= toStartOfDay(toDateTime({{from}}, 'UTC'))"
      assert query.sql =~ "dt < toStartOfDay(toDateTime({{to}}, 'UTC')) + INTERVAL 1 DAY"
      assert query.sql =~ "dt >= toDateTime({{from}}) AND dt < toDateTime({{to}})"
    end

    test "the same event of an actor is counted once per second" do
      query = SqlQuery.github_activity_v2_query(["org"], @from, @to, "1d")

      assert query.sql =~ "groupUniqArray(toUInt32(dt))"
      assert query.sql =~ "GROUP BY owner, repo, actor, event"
    end

    test "only dev_activity excludes the non-dev events" do
      dev_query = SqlQuery.dev_activity_v2_query(["org"], @from, @to, "1d")
      github_query = SqlQuery.github_activity_v2_query(["org"], @from, @to, "1d")

      assert dev_query.sql =~ "event NOT IN ({{non_dev_events}})"
      refute github_query.sql =~ "event NOT IN"
    end
  end

  describe "deduplication" do
    test "the events up to 3 seconds apart are paired" do
      for query <- all_v2_queries() do
        assert query.sql =~ "arraySort(groupUniqArray(toUInt32(dt))) AS timestamps"
        assert query.sql =~ "GROUP BY owner, repo, actor, event"
        assert query.sql =~ "AND NOT endsWith(actor, '[bot]')"
        assert query.sql =~ "if(i = 1 OR gap > 3, i, 0)"
        # every run of k events counts as ceil(k / 2)
        assert query.sql =~
                 "arrayFilter((t, i, start) -> (i - start) % 2 = 0, timestamps, positions, run_start_positions)"

        refute query.sql =~ "lagInFrame"
        refute query.sql =~ "row_number()"
        # runs can start before the first day of the time range
        assert query.sql =~ "toStartOfDay(toDateTime({{from}}, 'UTC')) - INTERVAL 600 SECOND"
      end
    end

    defp all_v2_queries() do
      [
        SqlQuery.dev_activity_v2_query(["org"], @from, @to, "1d"),
        SqlQuery.dev_activity_v2_query(["org"], @from, @to, "1h"),
        SqlQuery.github_activity_v2_query(["org"], @from, @to, "toStartOfMonth"),
        SqlQuery.total_dev_activity_v2_query(["org"], @from, @to),
        SqlQuery.total_github_activity_v2_query(["org"], @from, @to)
      ]
    end
  end

  describe "aggregated queries" do
    test "the upper bound matches the v1 queries" do
      dev_query = SqlQuery.total_dev_activity_v2_query(["org"], @from, @to)
      github_query = SqlQuery.total_github_activity_v2_query(["org"], @from, @to)

      assert dev_query.sql =~ "dt <= toDateTime({{to}})"
      assert github_query.sql =~ "dt < toDateTime({{to}})"
      assert dev_query.sql =~ "event NOT IN ({{non_dev_events}})"
      refute github_query.sql =~ "event NOT IN"
      # the zeros of the organizations without activity must be floats like the sums
      assert dev_query.sql =~ "toFloat64(0) AS value"
      assert github_query.sql =~ "toFloat64(0) AS value"
      assert dev_query.parameters[:from] == DateTime.to_unix(@from)
      assert dev_query.parameters[:to] == DateTime.to_unix(@to)
    end
  end

  describe "metrics" do
    test "dev_activity and github_activity have version 2.0" do
      for metric <- ["dev_activity", "github_activity"] do
        assert {:ok, ["1.0", "2.0"]} = Sanbase.Metric.available_versions(metric)
      end

      for metric <- ["dev_activity_contributors_count", "github_activity_contributors_count"] do
        assert {:ok, ["1.0"]} = Sanbase.Metric.available_versions(metric)
      end

      {:ok, versions} = Sanbase.Metric.available_versions()
      assert versions["dev_activity"] == ["1.0", "2.0"]
    end

    test "dev_activity version 2.0 timeseries" do
      rows = [
        [DateTime.to_unix(~U[2026-06-08 00:00:00Z]), 230.4],
        [DateTime.to_unix(~U[2026-06-09 00:00:00Z]), 50.25]
      ]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, result} =
                 Sanbase.Metric.timeseries_data(
                   "dev_activity",
                   %{organization: "org"},
                   ~U[2026-06-08 00:00:00Z],
                   @to,
                   "1d",
                   version: "2.0"
                 )

        assert result == [
                 %{datetime: ~U[2026-06-08 00:00:00Z], value: 230.4},
                 %{datetime: ~U[2026-06-09 00:00:00Z], value: 50.25}
               ]
      end)
    end

    test "github_activity version 2.0 aggregated timeseries" do
      rows = [["org1", 385.5], ["org2", 100]]

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, %{"org1" => 385.5, "org2" => 100.0}} =
                 Sanbase.Metric.aggregated_timeseries_data(
                   "github_activity",
                   %{organizations: ["org1", "org2"]},
                   @from,
                   @to,
                   version: "2.0"
                 )
      end)
    end

    test "the version selects the query" do
      test_pid = self()

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, _args, _opts ->
        send(test_pid, {:sql, sql})
        {:ok, %{rows: []}}
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        for version <- ["1.0", "2.0"] do
          assert {:ok, []} =
                   Sanbase.Metric.timeseries_data(
                     "dev_activity",
                     %{organization: "org"},
                     @from,
                     @to,
                     "1d",
                     version: version
                   )
        end

        assert_receive {:sql, v1_sql}
        assert_receive {:sql, v2_sql}
        refute v1_sql =~ "max_daily_events"
        assert v2_sql =~ "max_daily_events"
      end)
    end

    test "an unsupported version is an error" do
      assert {:error, error} =
               Sanbase.Metric.timeseries_data(
                 "dev_activity_contributors_count",
                 %{organization: "org"},
                 @from,
                 @to,
                 "1d",
                 version: "2.0"
               )

      assert error =~
               "Version 2.0 is not available for the dev_activity_contributors_count metric"

      assert {:error, _} =
               Sanbase.Metric.aggregated_timeseries_data(
                 "dev_activity",
                 %{organization: "org"},
                 @from,
                 @to,
                 version: "3.0"
               )
    end
  end
end
