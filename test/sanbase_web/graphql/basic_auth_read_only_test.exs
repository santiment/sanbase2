defmodule SanbaseWeb.Graphql.BasicAuthReadOnlyTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias SanbaseWeb.Graphql.Middlewares.BasicAuthReadOnly
  alias SanbaseWeb.Graphql.Schema

  setup do
    user = insert(:user)

    %{
      basic_conn: setup_basic_auth(build_conn(), "user", "pass"),
      jwt_conn: setup_jwt_auth(build_conn(), user),
      user: user
    }
  end

  describe "schema wiring" do
    test "every mutation is restricted" do
      %{fields: fields} = Absinthe.Schema.lookup_type(Schema, :mutation)

      assert map_size(fields) > 0

      for {name, _field} <- fields, name != :__typename do
        assert restricted?(:mutation, name), "mutation #{name} is not restricted"
      end
    end

    test "user-scoped and basic-auth-only queries are restricted" do
      for name <- [
            # UserAuth
            :run_raw_sql_query,
            :run_sql_query,
            :get_query_executions,
            # JWTAuth
            :get_clickhouse_query_execution_stats,
            # BasicAuth only
            :get_events_for_users,
            :api_metric_distribution,
            :api_metric_distribution_per_user,
            # Explicitly denied
            :current_user
          ] do
        assert restricted?(:query, name), "query #{name} is not restricted"
      end
    end

    test "public data queries are not restricted" do
      for name <- [:get_metric, :all_projects, :project_by_slug, :get_reports] do
        refute restricted?(:query, name), "query #{name} is restricted"
      end
    end
  end

  describe "basic auth requests" do
    test "cannot run mutations", context do
      mutation = """
      mutation {
        createDashboard(name: "Basic auth dashboard") { id }
      }
      """

      assert execute_mutation_with_error(context.basic_conn, mutation) ==
               BasicAuthReadOnly.error_msg()
    end

    test "cannot run raw SQL queries", context do
      query = """
      {
        runRawSqlQuery(sqlQueryText: "SELECT 1", sqlQueryParameters: "{}") { columns }
      }
      """

      %{"errors" => [error]} = execute_query(context.basic_conn, query)
      assert error["message"] == BasicAuthReadOnly.error_msg()
    end

    test "cannot read the current user", context do
      query = "{ currentUser { id } }"

      %{"data" => %{"currentUser" => nil}, "errors" => [error]} =
        execute_query(context.basic_conn, query)

      assert error["message"] == BasicAuthReadOnly.error_msg()
    end

    test "cannot read internal user events", context do
      query = """
      {
        getEventsForUsers(users: [#{context.user.id}]) { userId }
      }
      """

      %{"errors" => [error]} = execute_query(context.basic_conn, query)
      assert error["message"] == BasicAuthReadOnly.error_msg()
    end

    test "can read public data", context do
      insert(:project, slug: "santiment", name: "Santiment")

      query = "{ projectBySlug(slug: \"santiment\") { slug } }"

      assert %{"data" => %{"projectBySlug" => %{"slug" => "santiment"}}} =
               execute_query(context.basic_conn, query)
    end
  end

  describe "other auth methods are unaffected" do
    test "jwt user reads the current user", context do
      query = "{ currentUser { id } }"

      assert %{"data" => %{"currentUser" => %{"id" => id}}} =
               execute_query(context.jwt_conn, query)

      assert id == to_string(context.user.id)
    end

    test "jwt user runs mutations", context do
      mutation = """
      mutation {
        createDashboard(name: "Jwt dashboard") { id }
      }
      """

      assert %{"id" => _} = execute_mutation(context.jwt_conn, mutation)
    end
  end

  defp restricted?(object, field) do
    middleware =
      case Absinthe.Schema.lookup_type(Schema, object).fields[field].middleware do
        [{{Absinthe.Middleware, :shim}, _}] = shim -> Absinthe.Middleware.unshim(shim, Schema)
        middleware -> middleware
      end

    Enum.any?(middleware, &match?({BasicAuthReadOnly, _}, &1))
  end
end
