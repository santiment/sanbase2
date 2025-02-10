defmodule Sanbase.InsihgtVotingApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Insight.Post

  setup do
    insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())

    user = insert(:user)
    user2 = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)
    conn2 = setup_jwt_auth(build_conn(), user2)

    {:ok, %{insight: insight, user: user, conn: conn, conn2: conn2}}
  end

  test "voting for an insight", context do
    %{conn: conn, insight: insight} = context

    %{"votes" => %{"totalVotes" => total_votes_1}} = vote(conn, insight)

    for _ <- 1..15, do: vote(conn, insight)

    %{"votes" => %{"totalVotes" => total_votes_17}} = vote(conn, insight)

    for _ <- 1..5, do: vote(conn, insight)

    # This is over the 20th vote for this user but the vote cannot be bumped to more than 20
    %{"votedAt" => voted_at, "votes" => %{"totalVotes" => total_votes_20}} = vote(conn, insight)

    assert total_votes_1 == 1
    assert total_votes_17 == 17
    assert total_votes_20 == 20

    assert Sanbase.TestUtils.datetime_close_to(
             DateTime.utc_now(),
             Sanbase.DateTimeUtils.from_iso8601!(voted_at),
             5,
             :seconds
           )
  end

  test "current user votes for an insight", context do
    %{conn: conn, conn2: conn2, insight: insight} = context
    for _ <- 1..5, do: vote(conn2, insight)

    %{"votes" => %{"totalVotes" => total_votes_1, "currentUserVotes" => user_votes_1}} =
      vote(conn, insight)

    %{"votes" => %{"totalVotes" => total_votes_2, "currentUserVotes" => user_votes_2}} =
      vote(conn, insight)

    assert total_votes_1 == 6
    assert user_votes_1 == 1

    assert total_votes_2 == 7
    assert user_votes_2 == 2
  end

  test "current user votes for an insight for anon user", context do
    %{conn: conn, insight: insight} = context
    for _ <- 1..5, do: vote(conn, insight)

    new_conn = build_conn()

    %{"votes" => %{"totalVotes" => total_votes, "currentUserVotes" => current_user_votes}} =
      get_votes(new_conn, insight)

    assert total_votes == 5
    assert current_user_votes == nil
  end

  test "total voters", context do
    %{conn: conn, conn2: conn2, insight: insight} = context
    for _ <- 1..2, do: vote(conn, insight)
    for _ <- 1..3, do: vote(conn2, insight)

    %{"votes" => %{"totalVoters" => total_voters}} = vote(conn, insight)

    assert total_voters == 2
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

  defp get_votes(conn, %{id: insight_id}) do
    query = """
    {
      insight(id: #{insight_id}) {
        votedAt
        votes {
          totalVotes
          totalVoters
          currentUserVotes
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "insight"])
  end

  defp vote(conn, %{id: insight_id}) do
    mutation = """
    mutation {
      vote(insightId: #{insight_id}){
        votes{ totalVotes currentUserVotes totalVoters }
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
        votes{ totalVotes currentUserVotes totalVoters }
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
