defmodule SanbaseWeb.Graphql.WatchlistInvalidIdApiTest do
  # Reproduces SANBASE-BACKEND-PROD-G9W: a non-integer watchlist id (e.g. the
  # SQLi probe "1 OR 1") reaches Repo.get/2 uncast in
  # Sanbase.UserList.user_list/2 and raises Ecto.Query.CastError (500).
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  for id <- ["1 OR 1", "abc", "1; DROP TABLE user_lists"] do
    test "watchlist with invalid id #{inspect(id)} does not crash (authenticated)", %{conn: conn} do
      assert_clean_response(conn, unquote(id))
    end

    test "watchlist with invalid id #{inspect(id)} does not crash (anonymous)" do
      assert_clean_response(build_conn(), unquote(id))
    end
  end

  test "UserList.user_list/2 with an invalid id returns a tuple", %{user: user} do
    assert {_, nil_or_error} = Sanbase.UserList.user_list("1 OR 1", user)
    refute match?(%Sanbase.UserList{}, nil_or_error)
  end

  defp assert_clean_response(conn, id) do
    query = """
    {
      watchlist(id: "#{id}") { id name }
    }
    """

    result = execute_query(conn, query)

    # A not-found (null) result or a clean GraphQL error are both fine.
    assert get_in(result, ["data", "watchlist"]) == nil
  end
end
