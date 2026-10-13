defmodule SanbaseWeb.Graphql.ChatInvalidIdApiTest do
  use SanbaseWeb.ConnCase,
    async: false,
    parameterize: [%{field: "chat", arg: "id"}, %{field: "chatMessages", arg: "chatId"}]

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  test "a chat query with a non-UUID id returns not found", %{field: field, arg: arg} do
    conn = setup_jwt_auth(build_conn(), insert(:user))

    query = """
    {
      #{field}(#{arg}: "bitcoin") { id }
    }
    """

    assert execute_query_with_error(conn, query) == "Chat not found"
  end
end
