defmodule SanbaseWeb.Graphql.PublicTriggersForUserInvalidIdTest do
  use SanbaseWeb.ConnCase,
    async: false,
    parameterize:
      for(user_id <- ["ncMUFCMU", "1 OR 1", "99999999999999999999"], do: %{user_id: user_id})

  import SanbaseWeb.Graphql.TestHelpers

  test "publicTriggersForUser with an invalid userId returns an error", %{user_id: user_id} do
    query = """
    {
      publicTriggersForUser(userId: "#{user_id}") {
        userId
        trigger { id }
      }
    }
    """

    assert execute_query_with_error(build_conn(), query) == "Invalid user id: #{inspect(user_id)}"
  end
end
