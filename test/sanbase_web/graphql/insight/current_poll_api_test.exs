defmodule SanbaseWeb.Graphql.CurrentPollApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.{Poll, Post, Vote}
  alias Sanbase.Repo

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "getting the current poll" do
    query = """
    {
      currentPoll {
        startAt,
        endAt,
        posts {
          id
        }
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "currentPoll"))

    current_poll = json_response(result, 200)["data"]["currentPoll"]

    assert Timex.parse!(current_poll["startAt"], "{ISO:Extended}") ==
             Timex.beginning_of_week(Timex.now()) |> DateTime.truncate(:second)

    assert current_poll["posts"] == []
  end

  test "getting the current poll with some posts and votes", %{user: user} do
    poll = Poll.find_or_insert_current_poll!()

    approved_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    %Vote{post_id: approved_post.id, user_id: user.id}
    |> Repo.insert!()

    query = """
    {
      currentPoll {
        startAt
        endAt
        posts {
          id
        }
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "currentPoll"))

    current_poll = json_response(result, 200)["data"]["currentPoll"]

    assert DateTime.compare(
             Timex.parse!(current_poll["startAt"], "{ISO:Extended}"),
             Timex.beginning_of_week(Timex.now())
           ) == :eq

    assert %{"id" => Integer.to_string(approved_post.id)} in current_poll["posts"]
  end

  test "getting the current poll with the dates when the current user voted", %{
    user: user,
    conn: conn
  } do
    poll = Poll.find_or_insert_current_poll!()

    approved_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        link: "http://example.com",
        text: "Text of the post",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    vote =
      %Vote{post_id: approved_post.id, user_id: user.id}
      |> Repo.insert!()

    query = """
    {
      currentPoll {
        posts {
          id,
          voted_at
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentPoll"))

    current_poll = json_response(result, 200)["data"]["currentPoll"]
    [post] = current_poll["posts"]

    assert Timex.parse!(post["voted_at"], "{ISO:Extended}") == vote.inserted_at
  end
end
