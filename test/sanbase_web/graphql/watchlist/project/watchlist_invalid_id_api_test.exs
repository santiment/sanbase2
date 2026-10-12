defmodule SanbaseWeb.Graphql.WatchlistInvalidIdApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  for id <- ["1 OR 1", "abc", "1; DROP TABLE user_lists"],
      auth? <- [true, false] do
    test "watchlist with invalid id #{inspect(id)} is not found (authenticated: #{auth?})",
         %{conn: conn} do
      conn = if unquote(auth?), do: conn, else: build_conn()

      query = """
      {
        watchlist(id: "#{unquote(id)}") { id name }
      }
      """

      assert %{"data" => %{"watchlist" => nil}} = result = execute_query(conn, query)
      refute Map.has_key?(result, "errors")
    end
  end

  test "UserList.user_list/2 with an invalid id returns nil", %{user: user} do
    assert {:ok, nil} = Sanbase.UserList.user_list("1 OR 1", user)
  end
end
