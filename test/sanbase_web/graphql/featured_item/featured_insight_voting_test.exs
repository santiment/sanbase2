defmodule Sanbase.FeaturedInsihgtVotingTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.FeaturedItem
  alias Sanbase.Insight.Post

  setup do
    insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
    FeaturedItem.update_item(insight, true)

    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, %{insight: insight, user: user, conn: conn}}
  end

  test "voting for a featured insight", context do
    %{"data" => %{"featuredInsights" => [featured_insight]}} = featured_insights(context.conn)

    assert featured_insight["votedAt"] == nil

    %{"data" => %{"vote" => voted_insight}} = vote_for(context.conn, context.insight)
    voted_at = Sanbase.DateTimeUtils.from_iso8601!(voted_insight["votedAt"])

    assert Sanbase.TestUtils.datetime_close_to(
             voted_at,
             DateTime.utc_now(),
             seconds: 2
           )
  end

  defp vote_for(conn, %{id: insight_id}) do
    mutation = """
    mutation {
      vote(insightId: #{insight_id}){
        votedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp featured_insights(conn) do
    query = """
    {
      featuredInsights{
        id
        votedAt
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
