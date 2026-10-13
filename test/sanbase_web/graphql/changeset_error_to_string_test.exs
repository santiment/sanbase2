defmodule SanbaseWeb.Graphql.ChangesetErrorToStringTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.Post

  @moduletag capture_log: true

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "updateInsight with a too long title returns a GraphQL error", %{conn: conn, user: user} do
    post = insert(:post, user: user, ready_state: Post.draft())
    long_title = String.duplicate("a", 200)

    mutation = """
    mutation {
      updateInsight(id: #{post.id}, title: "#{long_title}") {
        id
        title
      }
    }
    """

    assert execute_mutation_with_error(conn, mutation) ==
             "Cannot update insight with id #{post.id}"
  end

  test "createChartConfiguration without a project returns a GraphQL error", %{conn: conn} do
    mutation = """
    mutation {
      createChartConfiguration(settings: {title: "No project config"}) {
        id
      }
    }
    """

    assert execute_mutation_with_error(conn, mutation) == "Cannot create chart configuration"
  end
end
