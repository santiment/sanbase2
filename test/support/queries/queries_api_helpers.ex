defmodule SanbaseWeb.QueriesApiHelpers do
  use SanbaseWeb.ConnCase, async: false
  import SanbaseWeb.Graphql.TestHelpers

  def execute_sql_query_mutation(conn, mutation, args \\ nil) do
    args =
      args ||
        %{
          name: "MyQuery",
          description: "some desc",
          is_public: true,
          sql_query_text:
            "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})",
          sql_query_parameters: %{slug: "bitcoin"},
          settings: %{"some_key" => [0, 1, 2, 3]}
        }

    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        name
        description
        user{ id }
        sqlQueryText
        sqlQueryParameters
        settings
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  def run_sql_query(conn, query, args) do
    query_name = query |> Inflex.camelize(:lower)

    mutation = """
    {
      #{query_name}(#{map_to_args(args)}){
        queryId
        dashboardQueryMappingId
        clickhouseQueryId
        columnTypes
        columns
        rows
        summary
        queryStartTime
        queryEndTime
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  def get_sql_query(conn, query_id) do
    query = """
    {
      getSqlQuery(id: #{query_id}){
        id
        name
        description
        isPublic
        settings
        user{ id }
        sqlQueryText
        sqlQueryParameters
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
