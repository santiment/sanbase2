defmodule SanbaseWeb.Graphql.GetMostRecentEmptyTypesTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  for {name, args, selection} <- [
        {"stats with empty types", "types: []", "stats { totalEntitiesCount }"},
        {"data with empty types", "types: []", "data { insight { id } }"},
        {"stats with neither type nor types", "", "stats { totalEntitiesCount }"}
      ] do
    test "getMostRecent #{name} returns a GraphQL error", %{conn: conn} do
      query = """
      {
        getMostRecent(#{unquote(args)} page: 1, pageSize: 10) {
          #{unquote(selection)}
        }
      }
      """

      assert execute_query_with_error(conn, query) =~ "At least one non-null entity type"
    end
  end
end
