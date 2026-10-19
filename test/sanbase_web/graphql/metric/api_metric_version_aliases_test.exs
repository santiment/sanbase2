defmodule SanbaseWeb.Graphql.ApiMetricVersionAliasesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.MetricVersionAliasHelpers, only: [create_alias!: 1, pit: 0]

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
    create_alias!(%{version_num: "7.1", version_name: "seven_pit:v1", plan_access: pit()})
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
    # A migrated test database already has this row (the migration seeds it); one
    # loaded from structure.sql does not.
    unless Sanbase.Repo.get_by(VersionAlias, version_num: "Experimental (Weighted Age)") do
      create_alias!(%{
        version_num: "Experimental (Weighted Age)",
        version_name: "experimental_weighted_age:v1"
      })
    end

    error =
      execute_query_with_error(
        ctx.conn,
        available_versions_query("experimental_weighted_age:v1"),
        "getMetric"
      )

    assert error =~ "only users with alpha access"
  end

  describe "availableVersions lists the versions exposed in the caller's product" do
    setup do
      create_alias!(%{version_num: "7.0", version_name: "seven:v1", exposed_in: "api_only"})
      create_alias!(%{version_num: "8.0", version_name: "eight:v1", exposed_in: "sanbase_only"})
      Sanbase.Cache.clear_all()
      :ok
    end

    test "in the metric metadata", ctx do
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(insert(:user))
      apikey_conn = setup_apikey_auth(build_conn(), apikey)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Metric.available_versions/1,
        {:ok, ["1.0", "7.0", "8.0"]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert version_nums(available_version_names(ctx.conn)) == ["1.0", "8.0"]
        assert version_nums(available_version_names(apikey_conn)) == ["1.0", "7.0"]
        assert version_nums(available_version_names(build_conn())) == ["1.0"]
      end)
    end

    test "in getAccessRestrictions, for the product asked about", ctx do
      Sanbase.Mock.prepare_mock2(
        &Sanbase.Metric.available_versions/0,
        {:ok, %{@metric => ["1.0", "7.0", "8.0"]}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert restriction_version_nums(ctx.conn, "SANAPI") == ["1.0", "7.0"]
        assert restriction_version_nums(ctx.conn, "SANBASE") == ["1.0", "8.0"]
      end)
    end
  end

  defp version_nums(versions), do: Enum.map(versions, & &1["versionNum"])

  defp restriction_version_nums(conn, product) do
    query = """
    {
      getAccessRestrictions(product: #{product}, filter: METRIC) {
        name
        availableVersions { versionNum }
      }
    }
    """

    conn
    |> execute_query(query, "getAccessRestrictions")
    |> Enum.find(&(&1["name"] == @metric))
    |> Map.fetch!("availableVersions")
    |> version_nums()
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
