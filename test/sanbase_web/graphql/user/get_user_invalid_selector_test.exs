defmodule SanbaseWeb.Graphql.GetUserInvalidSelectorTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  test "getUser with a valid numeric id still works", %{conn: conn, user: user} do
    assert execute_query(conn, get_user_query(~s|"#{user.id}"|), "getUser") == %{
             "id" => to_string(user.id)
           }
  end

  for bad_id <- [~s|"undefined"|, "null", ~s|"99999999999999999999"|] do
    test "getUser with invalid id #{bad_id} returns a GraphQL error, not a 500", %{conn: conn} do
      assert execute_query_with_error(conn, get_user_query(unquote(bad_id)), "getUser") =~
               "Invalid user id"
    end
  end

  defp get_user_query(id_literal) do
    """
    {
      getUser(selector: { id: #{id_literal} }) {
        id
      }
    }
    """
  end
end
