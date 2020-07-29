defmodule Sanbase.InsihgtVotingApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.Post

  setup do
    insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())

    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, %{insight: insight, user: user, conn: conn}}
  end

  test "voting for an insight", context do
    %{conn: conn, insight: insight} = context

    %{"votes" => %{"totalVotes" => total_votes_1}} = vote(conn, insight)

    for _ <- 1..15, do: vote(conn, insight)

    %{"votes" => %{"totalVotes" => total_votes_17}} = vote(conn, insight)

    for _ <- 1..5, do: vote(conn, insight)

    # This is over the 20th vote but the vote cannot be bumped to more than 20
    %{"votedAt" => voted_at, "votes" => %{"totalVotes" => total_votes_20}} = vote(conn, insight)

    assert total_votes_1 == 1
    assert total_votes_17 == 17
    assert total_votes_20 == 20

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             voted_at |> Sanbase.DateTimeUtils.from_iso8601!(),
             5,
             :seconds
           )
  end

  test "downvoting an insight", context do
    %{conn: conn, insight: insight} = context

    vote(conn, insight)
    vote(conn, insight)

    downvote(conn, insight)
    %{"votedAt" => voted_at, "votes" => %{"totalVotes" => total_votes}} = downvote(conn, insight)

    assert voted_at == nil
    assert total_votes == 0
  end

  defp vote(conn, %{id: insight_id}) do
    mutation = """
    mutation {
      vote(insightId: #{insight_id}){
        votes{ totalVotes }
        votedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "vote"])
  end

  defp downvote(conn, %{id: insight_id}) do
    mutation = """
    mutation {
      unvote(insightId: #{insight_id}){
        votes{ totalVotes }
        votedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "unvote"])
  end
end
