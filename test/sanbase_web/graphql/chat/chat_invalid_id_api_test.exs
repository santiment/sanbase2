defmodule SanbaseWeb.Graphql.ChatInvalidIdApiTest do
  # Reproduces SANBASE-BACKEND-PROD-G16: a non-UUID chat id reaches Ecto
  # uncast and raises Ecto.Query.CastError (500) instead of a GraphQL error.
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  for chat_id <- ["1", "bitcoin", "1 OR 1"] do
    test "chatMessages with non-UUID chatId #{inspect(chat_id)} returns an error", %{conn: conn} do
      query = """
      {
        chatMessages(chatId: "#{unquote(chat_id)}") { id }
      }
      """

      result = execute_query(conn, query)

      assert get_in(result, ["data", "chatMessages"]) == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert is_binary(message)
    end

    test "chat with non-UUID id #{inspect(chat_id)} returns an error", %{conn: conn} do
      query = """
      {
        chat(id: "#{unquote(chat_id)}") { id }
      }
      """

      result = execute_query(conn, query)

      assert get_in(result, ["data", "chat"]) == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert is_binary(message)
    end

    test "anonymous chatMessages with non-UUID chatId #{inspect(chat_id)} returns an error" do
      query = """
      {
        chatMessages(chatId: "#{unquote(chat_id)}") { id }
      }
      """

      result = execute_query(build_conn(), query)

      assert get_in(result, ["data", "chatMessages"]) == nil
      assert [%{"message" => message} | _] = result["errors"]
      assert is_binary(message)
    end
  end
end
