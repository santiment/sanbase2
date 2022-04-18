defmodule Sanbase.Alert.TriggerVotingTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "user trigger voting", context do
    %{conn: conn} = context

    user_trigger = insert(:user_trigger, is_public: true)

    result = get_votes(conn, user_trigger.id)

    assert result["votedAt"] == nil

    assert result["votes"] == %{
             "currentUserVotes" => 0,
             "totalVoters" => 0,
             "totalVotes" => 0
           }

    %{"data" => %{"vote" => vote}} = vote(conn, user_trigger.id, direction: :up)

    result = get_votes(conn, user_trigger.id)

    assert result["votedAt"] == vote["votedAt"]
    voted_at = vote["votedAt"] |> Sanbase.DateTimeUtils.from_iso8601!()
    assert Sanbase.TestUtils.datetime_close_to(voted_at, Timex.now(), seconds: 2)
    assert vote["votes"] == result["votes"]
    assert vote["votes"] == %{"currentUserVotes" => 1, "totalVoters" => 1, "totalVotes" => 1}

    %{"data" => %{"vote" => vote}} = vote(conn, user_trigger.id, direction: :up)
    result = get_votes(conn, user_trigger.id)

    assert vote["votes"] == result["votes"]
    assert vote["votes"] == %{"currentUserVotes" => 2, "totalVoters" => 1, "totalVotes" => 2}

    %{"data" => %{"unvote" => vote}} = vote(conn, user_trigger.id, direction: :down)

    result = get_votes(conn, user_trigger.id)

    assert vote["votes"] == result["votes"]
    assert vote["votes"] == %{"currentUserVotes" => 1, "totalVoters" => 1, "totalVotes" => 1}

    %{"data" => %{"unvote" => vote}} = vote(conn, user_trigger.id, direction: :down)

    result = get_votes(conn, user_trigger.id)

    assert vote["votes"] == result["votes"]
    assert vote["votedAt"] == nil
    assert vote["votes"] == %{"currentUserVotes" => 0, "totalVoters" => 0, "totalVotes" => 0}
  end

  defp get_votes(conn, user_trigger_id) do
    query = """
    {
      getTriggerById(id: #{user_trigger_id}){
        trigger{ id }
        votedAt
        votes { currentUserVotes totalVotes totalVoters }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getTriggerById"])
  end

  defp vote(conn, user_trigger_id, opts) do
    function =
      case Keyword.get(opts, :direction, :up) do
        :up -> "vote"
        :down -> "unvote"
      end

    mutation = """
    mutation {
      #{function}(userTriggerId: #{user_trigger_id}){
        votedAt
        votes { currentUserVotes totalVotes totalVoters }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
