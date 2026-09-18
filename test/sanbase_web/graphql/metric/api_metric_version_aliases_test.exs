defmodule SanbaseWeb.Graphql.ApiMetricVersionAliasesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1]

  alias Sanbase.Metric.VersionAlias

  @metric "daily_active_addresses"

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    project = insert(:random_project)

    VersionAlias.clear_cache()

    [
      conn: setup_jwt_auth(build_conn(), user),
      slug: project.slug,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z]
    ]
  end

  test "a version name and its number reach the adapter as the same canonical version", ctx do
    create_alias!(%{version_num: "7.1", version_name: "seven_pit:v1"})
    test_pid = self()

    Sanbase.Mock.prepare_mock(
      Sanbase.Clickhouse.MetricAdapter,
      :aggregated_timeseries_data,
      fn _metric, _selector, _from, _to, opts ->
        send(test_pid, {:adapter_version, Keyword.get(opts, :version)})
        {:ok, %{ctx.slug => 100.0}}
      end
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert %{"aggregatedTimeseriesData" => 100.0} =
               execute_query(ctx.conn, aggregated_query(ctx, "seven_pit:v1"), "getMetric")

      assert_receive {:adapter_version, "7.1"}

      # Same canonical version, so the same GraphQL cache entry.
      SanbaseWeb.Graphql.Cache.clear_all()

      assert %{"aggregatedTimeseriesData" => 100.0} =
               execute_query(ctx.conn, aggregated_query(ctx, "7.1"), "getMetric")

      assert_receive {:adapter_version, "7.1"}
    end)
  end

  test "availableVersions returns the number, the name and the description", ctx do
    create_alias!(%{
      version_num: "7.1",
      version_name: "seven_pit:v1",
      description: "Point-in-time seven"
    })

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_versions/1, {:ok, ["7.0", "7.1"]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      versions =
        ctx.conn
        |> execute_query(available_versions_query(nil), "getMetric")
        |> get_in(["metadata", "availableVersions"])

      assert %{
               "version" => "7.1",
               "versionNum" => "7.1",
               "versionName" => "seven_pit:v1",
               "description" => "Point-in-time seven"
             } in versions

      assert %{
               "version" => "7.0",
               "versionNum" => "7.0",
               "versionName" => "7.0",
               "description" => nil
             } in versions
    end)
  end

  test "an alias edit is visible on the next request, without waiting for the GraphQL cache",
       ctx do
    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_versions/1, {:ok, ["7.1"]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert [%{"versionName" => "7.1"}] = available_version_names(ctx.conn)

      create_alias!(%{version_num: "7.1", version_name: "seven_pit:v1"})

      assert [%{"versionName" => "seven_pit:v1"}] = available_version_names(ctx.conn)
    end)
  end

  test "an unknown version name is rejected with the known names", ctx do
    create_alias!(%{version_num: "7.1", version_name: "seven_pit:v1"})

    error =
      execute_query_with_error(ctx.conn, available_versions_query("nope_pit:v9"), "getMetric")

    assert error =~ ~s("nope_pit:v9" is not a known version name)
    assert error =~ "seven_pit:v1"
  end

  test "the Experimental alias is normalized before the alpha-only access check", ctx do
    :ok = VersionAlias.seed_defaults()

    error =
      execute_query_with_error(
        ctx.conn,
        available_versions_query("experimental_weighted_age:v1"),
        "getMetric"
      )

    assert error =~ "only users with alpha access"
  end

  defp available_version_names(conn) do
    conn
    |> execute_query(available_versions_query(nil), "getMetric")
    |> get_in(["metadata", "availableVersions"])
  end

  defp aggregated_query(%{slug: slug, from: from, to: to}, version) do
    """
    {
      getMetric(metric: "#{@metric}", version: "#{version}") {
        aggregatedTimeseriesData(
          slug: "#{slug}"
          from: "#{DateTime.to_iso8601(from)}"
          to: "#{DateTime.to_iso8601(to)}"
          aggregation: LAST
        )
      }
    }
    """
  end

  defp available_versions_query(version) do
    version_arg = if version, do: ~s(, version: "#{version}"), else: ""

    """
    {
      getMetric(metric: "#{@metric}"#{version_arg}) {
        metadata { availableVersions { version versionNum versionName description } }
      }
    }
    """
  end
end
