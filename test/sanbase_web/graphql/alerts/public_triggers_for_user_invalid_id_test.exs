defmodule SanbaseWeb.Graphql.PublicTriggersForUserInvalidIdTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  test "publicTriggersForUser with a non-integer userId returns an error" do
    query = """
    {
      publicTriggersForUser(userId: "ncMUFCMU") {
        userId
      }
    }
    """

    assert execute_query_with_error(build_conn(), query) == ~s(Invalid user id: "ncMUFCMU")
  end
end
