defmodule SanbaseWeb.DashboardsApiHelpers do
  @moduledoc false
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  def execute_dashboard_mutation(conn, mutation, args \\ nil) do
    args =
      args ||
        %{
          name: "MyDashboard",
          description: "some text",
          is_public: true,
          settings: %{"some_key" => [0, 1, 2, 3]}
        }

    mutation_name = Inflex.camelize(mutation, :lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}) {
        id
        name
        description
        user { id }
        queries { id }
        textWidgets { id name description body }
        settings
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  def execute_global_parameter_mutation(conn, mutation, args) do
    mutation_name = Inflex.camelize(mutation, :lower)

    mutation = """
    mutation{
      #{mutation_name}(#{map_to_args(args)}){
        parameters
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  def execute_dashboard_query_mutation(conn, mutation, args) do
    mutation_name = Inflex.camelize(mutation, :lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        query{ id sqlQueryText sqlQueryParameters user { id } }
        dashboard { id parameters user { id } }
        settings
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  def cache_dashboard_query_execution(conn, args) do
    mutation = """
    mutation{
      storeDashboardQueryExecution(#{map_to_args(args)}){
        queries{
          queryId
          dashboardQueryMappingId
          clickhouseQueryId
          columns
          rows
          columnTypes
          queryStartTime
          queryEndTime
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  def get_cached_dashboard_queries_executions(conn, args) do
    query = """
    {
      getCachedDashboardQueriesExecutions(#{map_to_args(args)}){
        queries{
          queryId
          dashboardQueryMappingId
          clickhouseQueryId
          columnTypes
          columns
          rows
          queryStartTime
          queryEndTime
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  def get_dashboard(conn, dashboard_id) do
    query = """
    {
      getDashboard(id: #{dashboard_id}){
        id
        name
        description
        isPublic
        settings
        user{ id }
        queries {
          id
          sqlQueryText
          sqlQueryParameters
          settings
          user{ id }
        }
        votes {
          totalVotes
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
