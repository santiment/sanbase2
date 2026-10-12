defmodule SanbaseWeb.Graphql.PublicTriggersForUserInvalidIdTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  for user_id <- ["ncMUFCMU", "1 OR 1", "99999999999999999999"] do
    test "publicTriggersForUser with userId #{inspect(user_id)} returns an error" do
      query = """
      {
        publicTriggersForUser(userId: "#{unquote(user_id)}") {
          userId
          trigger { id }
        }
      }
      """

      assert execute_query_with_error(build_conn(), query) ==
               "Invalid user id: #{inspect(unquote(user_id))}"
    end
  end
end
