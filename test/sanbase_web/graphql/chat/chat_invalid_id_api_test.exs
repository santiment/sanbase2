defmodule SanbaseWeb.Graphql.ChatInvalidIdApiTest do
  use SanbaseWeb.ConnCase,
    async: false,
    parameterize:
      for(
        chat_id <- ["1", "bitcoin", "1 OR 1"],
        {field, arg, auth?} <- [
          {"chatMessages", "chatId", true},
          {"chat", "id", true},
          {"chatMessages", "chatId", false}
        ],
        do: %{chat_id: chat_id, field: field, arg: arg, auth?: auth?}
      )

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "a chat query with a non-UUID id returns an error", context do
    %{chat_id: chat_id, field: field, arg: arg, auth?: auth?} = context
    conn = if auth?, do: context.conn, else: build_conn()

    query = """
    {
      #{field}(#{arg}: "#{chat_id}") { id }
    }
    """

    assert %{"data" => %{^field => nil}, "errors" => [%{"message" => message} | _]} =
             execute_query(conn, query)

    assert is_binary(message)
  end
end
