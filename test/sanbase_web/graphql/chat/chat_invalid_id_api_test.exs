defmodule SanbaseWeb.Graphql.ChatInvalidIdApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  for chat_id <- ["1", "bitcoin", "1 OR 1"],
      {field, arg, auth?} <- [
        {"chatMessages", "chatId", true},
        {"chat", "id", true},
        {"chatMessages", "chatId", false}
      ] do
    test "#{field} with non-UUID #{arg} #{inspect(chat_id)} returns an error (authenticated: #{auth?})",
         %{conn: conn} do
      conn = if unquote(auth?), do: conn, else: build_conn()

      query = """
      {
        #{unquote(field)}(#{unquote(arg)}: "#{unquote(chat_id)}") { id }
      }
      """

      assert %{"data" => %{unquote(field) => nil}, "errors" => [%{"message" => message} | _]} =
               execute_query(conn, query)

      assert is_binary(message)
    end
  end
end
