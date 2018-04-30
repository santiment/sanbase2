defmodule SanbaseWeb.Graphql.VotingTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{
        salt: User.generate_salt(),
        san_balance: Decimal.new("10.000000000000000000"),
        san_balance_updated_at: Timex.now()
      }
      |> Repo.insert!()

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

    currentPoll = json_response(result, 200)["data"]["currentPoll"]

    assert Timex.parse!(currentPoll["startAt"], "{ISO:Extended}") ==
             Timex.beginning_of_week(Timex.now())

    assert currentPoll["posts"] == []
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
        startAt,
        endAt,
        posts {
          id,
          totalSanVotes
        }
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "currentPoll"))

    currentPoll = json_response(result, 200)["data"]["currentPoll"]

    assert Timex.parse!(currentPoll["startAt"], "{ISO:Extended}") ==
             Timex.beginning_of_week(Timex.now())

    assert currentPoll["posts"] == [
             %{
               "id" => Integer.to_string(approved_post.id),
               "totalSanVotes" => Decimal.to_string(user.san_balance)
             }
           ]
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

    currentPoll = json_response(result, 200)["data"]["currentPoll"]
    [post] = currentPoll["posts"]

    assert Timex.parse!(post["voted_at"], "{ISO:Extended}") == vote.inserted_at
  end

  test "voting for a post", %{conn: conn, user: user} do
    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        text: "Example MD text of the analysis",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    query = """
    mutation {
      vote(postId: #{sanbase_post.id}) {
        id,
        totalSanVotes
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    sanbasePost = json_response(result, 200)["data"]["vote"]

    assert sanbasePost["id"] == Integer.to_string(sanbase_post.id)

    assert sanbasePost["totalSanVotes"] == Decimal.to_string(user.san_balance)
  end

  test "unvoting for a post", %{conn: conn, user: user} do
    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        text: "Some text here",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    %Vote{post_id: sanbase_post.id, user_id: user.id}
    |> Repo.insert!()

    query = """
    mutation {
      unvote(postId: #{sanbase_post.id}) {
        id,
        totalSanVotes
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    sanbasePost = json_response(result, 200)["data"]["unvote"]

    assert sanbasePost["id"] == Integer.to_string(sanbase_post.id)
    assert Decimal.cmp(sanbasePost["totalSanVotes"] |> Decimal.new(), Decimal.new(0)) == :eq
  end
end
