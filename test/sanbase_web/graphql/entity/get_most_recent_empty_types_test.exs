defmodule SanbaseWeb.Graphql.GetMostRecentEmptyTypesTest do
  # Reproduces SANBASE-BACKEND-PROD-DSA:
  #   FunctionClauseError: no function clause matching in
  #   Sanbase.Entity.do_get_most_recent_total_count/2
  #
  # `types: []` passes GraphQL validation (`list_of(:entity_type)`), the resolver
  # forwards `[]` to `Sanbase.Entity`, and every `do_get_most_*` function only
  # has a clause guarded by `entities != []`, so the request crashes with a 500.
  # The desired behaviour is a regular GraphQL error (bad user input).
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  test "getMostRecent stats with an empty types list returns a GraphQL error", %{conn: conn} do
    query = """
    {
      getMostRecent(types: [], page: 1, pageSize: 10) {
        stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
      }
    }
    """

    result = execute(conn, query)

    assert [%{"message" => message} | _] = result["errors"]
    assert message =~ ~r/type/i
  end

  test "getMostRecent data with an empty types list returns a GraphQL error", %{conn: conn} do
    query = """
    {
      getMostRecent(types: [], page: 1, pageSize: 10) {
        data { insight { id } }
      }
    }
    """

    result = execute(conn, query)

    assert [%{"message" => message} | _] = result["errors"]
    assert message =~ ~r/type/i
  end

  test "getMostRecent with neither type nor types returns a GraphQL error", %{conn: conn} do
    query = """
    {
      getMostRecent(page: 1, pageSize: 10) {
        stats { totalEntitiesCount }
      }
    }
    """

    result = execute(conn, query)

    assert [%{"message" => message} | _] = result["errors"]
    assert message =~ ~r/type/i
  end

  defp execute(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
