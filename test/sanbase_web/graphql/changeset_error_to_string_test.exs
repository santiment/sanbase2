defmodule SanbaseWeb.Graphql.ChangesetErrorToStringTest do
  # Reproduces SANBASE-BACKEND-PROD-CX4:
  # Protocol.UndefinedError: protocol String.Chars not implemented for Ecto.Changeset
  #
  # Absinthe calls `to_string/1` on the value of `{:error, value}` returned by a
  # resolver. Some resolvers return the raw `%Ecto.Changeset{}` (or a tuple) instead of a
  # string / keyword list, so the whole request crashes with a 500 instead of returning
  # a GraphQL validation error. Seen in production for:
  #   * updateInsight with a title longer than 140 chars
  #     (Sanbase.Insight.Post.update/3 returns `{:error, changeset}` from Repo.update)
  #   * createChartConfiguration without a project
  #     (Sanbase.Chart.Configuration.create/1 returns Repo.insert's `{:error, changeset}`)
  #   * a `{:missing_contract, "..."}` tuple for slug "avalanche" (resolver not identified)
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

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)

    assert %{"data" => %{"updateInsight" => nil}, "errors" => [error | _]} = result
    assert is_binary(error["message"])
  end

  test "createChartConfiguration without a project returns a GraphQL error", %{conn: conn} do
    mutation = """
    mutation {
      createChartConfiguration(settings: {title: "No project config"}) {
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(mutation))
      |> json_response(200)

    assert %{"data" => %{"createChartConfiguration" => nil}, "errors" => [error | _]} = result
    assert is_binary(error["message"])
  end

  # Sanbase.Transfers.top_transfers/6 returns `{:error, {:missing_contract, msg}}` and
  # BlockchainAddressResolver.top_transfers/3 passes it through unchanged.
  test "topTransfers for a slug without contract returns a GraphQL error", %{conn: conn} do
    query = """
    {
      topTransfers(
        slug: "no-such-project-#{System.unique_integer([:positive])}"
        from: "2026-01-01T00:00:00Z"
        to: "2026-01-02T00:00:00Z"
      ) {
        trxValue
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)

    assert %{"data" => %{"topTransfers" => nil}, "errors" => [error | _]} = result
    assert is_binary(error["message"])
  end
end
