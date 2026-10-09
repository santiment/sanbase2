defmodule SanbaseWeb.Graphql.GetUserInvalidSelectorTest do
  # Reproduces SANBASE-BACKEND-PROD-11H:
  # FunctionClauseError in Sanbase.Accounts.User.by_id/2
  #
  # `getUser(selector: {id: ...})` goes through User.by_selector/2, which calls
  # `by_id(Sanbase.Math.to_integer(id), opts)`. For a non-numeric id
  # `Sanbase.Math.to_integer/1` returns `{:error, _}` and for `null` it returns
  # `nil` - neither matches a `by_id/2` clause, so the request crashes with a 500
  # instead of returning a GraphQL error.
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  test "getUser with a valid numeric id still works", %{conn: conn, user: user} do
    result = get_user(conn, ~s|"#{user.id}"|)

    assert %{"data" => %{"getUser" => %{"id" => id}}} = result
    assert id == to_string(user.id)
  end

  for bad_id <- [~s|"undefined"|, ~s|"null"|, ~s|"abc"|, ~s|""|, "null"] do
    test "getUser with invalid id #{bad_id} returns a GraphQL error, not a 500", %{conn: conn} do
      result = get_user(conn, unquote(bad_id))

      assert %{"data" => %{"getUser" => nil}, "errors" => [%{"message" => message} | _]} =
               result

      assert is_binary(message)
    end
  end

  defp get_user(conn, id_literal) do
    query = """
    {
      getUser(selector: { id: #{id_literal} }) {
        id
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "getUser"))
    |> json_response(200)
  end
end
