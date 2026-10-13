defmodule SanbaseWeb.Graphql.GetMostRecentEmptyTypesTest do
  use SanbaseWeb.ConnCase,
    async: false,
    parameterize: [
      %{args: "types: []", selection: "data { insight { id } }"},
      %{args: "", selection: "stats { totalEntitiesCount }"}
    ]

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn}
  end

  test "getMostRecent without entity types returns a GraphQL error", context do
    query = """
    {
      getMostRecent(#{context.args} page: 1, pageSize: 10) {
        #{context.selection}
      }
    }
    """

    assert execute_query_with_error(context.conn, query) =~ "At least one non-null entity type"
  end
end
