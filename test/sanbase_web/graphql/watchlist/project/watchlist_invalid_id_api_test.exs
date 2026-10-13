defmodule SanbaseWeb.Graphql.WatchlistInvalidIdApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  test "watchlist with a non-integer id is not found" do
    conn = setup_jwt_auth(build_conn(), insert(:user))

    query = """
    {
      watchlist(id: "1 OR 1") { id name }
    }
    """

    assert %{"data" => %{"watchlist" => nil}} = result = execute_query(conn, query)
    refute Map.has_key?(result, "errors")
  end

  test "UserList.by_id/2 with a non-integer id returns an error" do
    assert Sanbase.UserList.by_id("1 OR 1", []) ==
             {:error, "Watchlist with id 1 OR 1 does not exist"}
  end
end
