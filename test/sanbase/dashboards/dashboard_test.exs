defmodule Sanbase.DashboardsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Dashboards
  alias Sanbase.Queries

  setup do
    user = insert(:user)
    user2 = insert(:user)

    assert {:ok, query} =
             Queries.create_query(
               %{
                 sql_query_text: "SELECT * FROM metrics WHERE slug = {{slug}} LIMIT {{limit}}",
                 sql_query_parameters: %{"slug" => "ethereum", "limit" => 20}
               },
               user.id
             )

    query_metadata = Queries.QueryMetadata.from_local_dev(user.id)

    sql_query_text =
      "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}}) LIMIT {{limit}}"

    sql_query_parameters = %{slug: "bitcoin", limit: 2}

    {:ok, dashboard} =
      Dashboards.create_dashboard(%{name: "My dashboard", is_public: false}, user.id)

    {:ok, dashboard_query_mapping} =
      Dashboards.add_query_to_dashboard(dashboard.id, query.id, user.id)

    %{
      user: user,
      user2: user2,
      query: query,
      dashboard: dashboard,
      dashboard_query_mapping: dashboard_query_mapping,
      query_metadata: query_metadata,
      sql_query_text: sql_query_text,
      sql_query_parameters: sql_query_parameters
    }
  end

  describe "Dashboards CRUD" do
    test "read dashboard", context do
      %{dashboard: dashboard, user: user, user2: user2} = context

      # Get own private dashboard
      {:ok, fetched_dashboard} = Dashboards.get_dashboard(dashboard.id, user.id)
      assert fetched_dashboard.id == dashboard.id
      assert fetched_dashboard.name == dashboard.name
      assert fetched_dashboard.is_public == false

      # Cannot get other user private dashboard
      {:error, error_msg} = Dashboards.get_dashboard(dashboard.id, user2.id)
      assert error_msg =~ "does not exist, or it is private and owned by another user"

      # Can get other user public dashboard
      {:ok, dashboard} =
        Dashboards.update_dashboard(dashboard.id, %{is_public: true}, user.id)

      {:ok, fetched_dashboard} = Dashboards.get_dashboard(dashboard.id, user2.id)
      assert fetched_dashboard.id == dashboard.id
      assert fetched_dashboard.name == dashboard.name
      assert fetched_dashboard.is_public == true
    end

    test "create dashboard", context do
      %{user: user} = context

      create_args = %{
        name: "My Dashboard",
        description: "Dashboard description",
        is_public: false,
        settings: %{"some_var" => "some_value"}
      }

      # The returned object is the created dashboard
      {:ok, dashboard} = Dashboards.create_dashboard(create_args, user.id)
      assert dashboard.name == "My Dashboard"
      assert dashboard.description == "Dashboard description"
      assert dashboard.is_public == false
      assert dashboard.settings == %{"some_var" => "some_value"}
      assert dashboard.user_id == user.id

      # The dashboard is stored in the DB
      {:ok, fetched_dashboard} = Dashboards.get_dashboard(dashboard.id, user.id)
      assert fetched_dashboard.name == "My Dashboard"
      assert fetched_dashboard.description == "Dashboard description"
      assert fetched_dashboard.is_public == false
      assert fetched_dashboard.settings == %{"some_var" => "some_value"}
    end

    test "update dashboard", context do
      %{dashboard: dashboard, user: user, user2: user2} = context

      update_args = %{
        name: "New Name",
        description: "New description",
        is_public: true,
        settings: %{"some_var" => "some_value2"}
      }

      # Update user's own dashboard
      {:ok, dashboard} = Dashboards.update_dashboard(dashboard.id, update_args, user.id)
      assert dashboard.name == "New Name"
      assert dashboard.description == "New description"
      assert dashboard.is_public == true
      assert dashboard.settings == %{"some_var" => "some_value2"}
      assert dashboard.user_id == user.id

      {:ok, fetched_dashboard} = Dashboards.get_dashboard(dashboard.id, user.id)
      assert fetched_dashboard.name == "New Name"
      assert fetched_dashboard.description == "New description"
      assert fetched_dashboard.is_public == true
      assert fetched_dashboard.settings == %{"some_var" => "some_value2"}
      assert fetched_dashboard.user_id == user.id

      # Cannot update other users dashboards
      {:error, error_msg} =
        Dashboards.update_dashboard(dashboard.id, update_args, user2.id)

      assert error_msg =~ "does not exist, or it is owned by another user"
    end

    test "delete dashboard", context do
      %{dashboard: dashboard, user: user, user2: user2} = context

      # Cannot delete other users dashboards
      {:error, error_msg} = Dashboards.delete_dashboard(dashboard.id, user2.id)
      assert error_msg =~ "does not exist, or it is owned by another user"

      # Can delete own dashboard
      assert {:ok, _} = Dashboards.delete_dashboard(dashboard.id, user.id)

      assert {:error, error_msg} = Dashboards.get_dashboard(dashboard.id, user.id)
      assert error_msg =~ "does not exist, or it is private and owned by another user"
    end
  end

  describe "Dashboard Queries Caching" do
    test "cache dashboard queries", context do
      %{
        query: %{id: query_id} = query,
        dashboard_query_mapping: %{id: dashboard_query_mapping_id} = dashboard_query_mapping,
        dashboard: %{id: dashboard_id} = dashboard,
        user: user,
        query_metadata: query_metadata
      } = context

      (&Sanbase.ClickhouseRepo.query/2)
      |> Sanbase.Mock.prepare_mock2({:ok, result_mock()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, result} =
          Queries.run_query(query, user, query_metadata, store_execution_details: false)

        {:ok, dashboard_cache} =
          Dashboards.cache_dashboard_query_execution(
            dashboard.id,
            _parameters_override = %{},
            dashboard_query_mapping.id,
            result,
            user.id
          )

        assert %Dashboards.DashboardCache{
                 queries: %{},
                 inserted_at: _,
                 updated_at: _
               } = dashboard_cache
      end)

      # Test outside of the mock to make sure no database queries are made
      {:ok, dashboard_cache} =
        Dashboards.get_cached_dashboard_queries_executions(
          dashboard.id,
          _parameters_override = %{},
          user.id
        )

      assert %Dashboards.DashboardCache{
               queries: %{},
               inserted_at: _,
               updated_at: _
             } = dashboard_cache

      assert %{
               query_id: ^query_id,
               dashboard_query_mapping_id: ^dashboard_query_mapping_id,
               clickhouse_query_id: "1774C4BC91E05698",
               column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
               columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
               dashboard_id: ^dashboard_id,
               query_end_time: _,
               query_start_time: _,
               rows: [
                 [
                   1482,
                   1645,
                   ~U[1970-01-01 00:00:00Z],
                   0.045183932486757644,
                   ~U[2023-07-26 13:10:51Z]
                 ],
                 [
                   1482,
                   1647,
                   ~U[1970-01-01 00:00:00Z],
                   -0.13018891098082416,
                   ~U[2023-07-25 20:27:06Z]
                 ]
               ],
               summary: %{
                 "read_bytes" => 408_534.0,
                 "read_rows" => 12_667.0,
                 "result_bytes" => +0.0,
                 "result_rows" => +0.0,
                 "total_rows_to_read" => 4475.0,
                 "written_bytes" => +0.0,
                 "written_rows" => +0.0
               },
               updated_at: _
             } = dashboard_cache.queries[dashboard_query_mapping.id]
    end

    test "cannot update other people dashboard cache via cacheDashboardQueryExection", context do
      %{
        query: query,
        dashboard_query_mapping: dashboard_query_mapping,
        dashboard: dashboard,
        user2: user2,
        query_metadata: query_metadata
      } = context

      (&Sanbase.ClickhouseRepo.query/2)
      |> Sanbase.Mock.prepare_mock2({:ok, result_mock()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, result} =
                 Sanbase.Queries.run_query(query, user2, query_metadata, store_execution_details: false)

        assert {:error, error_msg} =
                 Sanbase.Dashboards.cache_dashboard_query_execution(
                   dashboard.id,
                   _parameters_override = %{},
                   dashboard_query_mapping.id,
                   result,
                   user2.id
                 )

        assert error_msg =~
                 "Dashboard does not exist, or it is private and owned by another user."
      end)
    end
  end

  defp result_mock do
    %Clickhousex.Result{
      query_id: "1774C4BC91E05698",
      summary: %{
        "read_bytes" => "408534",
        "read_rows" => "12667",
        "result_bytes" => "0",
        "result_rows" => "0",
        "total_rows_to_read" => "4475",
        "written_bytes" => "0",
        "written_rows" => "0"
      },
      command: :selected,
      columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
      column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
      rows: [
        [1482, 1645, ~N[1970-01-01 00:00:00], 0.045183932486757644, ~N[2023-07-26 13:10:51]],
        [1482, 1647, ~N[1970-01-01 00:00:00], -0.13018891098082416, ~N[2023-07-25 20:27:06]]
      ],
      num_rows: 2
    }
  end
end
