defmodule SanbaseWeb.Graphql.VotingTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.InternalServices.Ethauth

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{
        salt: User.generate_salt(),
        san_balance:
          Decimal.mult(Decimal.new("10.000000000000000000"), Ethauth.san_token_decimals()),
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
        link: "http://example.com",
        approved_at: Timex.now()
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
               "totalSanVotes" =>
                 Decimal.to_string(Decimal.div(user.san_balance, Ethauth.san_token_decimals()))
             }
           ]
  end

  test "voting for a post", %{conn: conn, user: user} do
    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        link: "http://example.com",
        approved_at: Timex.now()
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

    assert sanbasePost["totalSanVotes"] ==
             Decimal.to_string(Decimal.div(user.san_balance, Ethauth.san_token_decimals()))
  end

  test "unvoting for a post", %{conn: conn, user: user} do
    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        link: "http://example.com",
        approved_at: Timex.now()
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
    assert sanbasePost["totalSanVotes"] == "0.000000000000000000"
  end

  test "adding a new post to the current poll", %{user: user, conn: conn} do
    query = """
    mutation {
      createPost(title: "Awesome post", link: "http://example.com") {
        id,
        title,
        link,
        user {
          id
        },
        totalSanVotes,
        approvedAt
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    sanbasePost = json_response(result, 200)["data"]["createPost"]

    assert sanbasePost["id"] != nil
    assert sanbasePost["title"] == "Awesome post"
    assert sanbasePost["approvedAt"] == nil
    assert sanbasePost["user"]["id"] == Integer.to_string(user.id)
    assert sanbasePost["totalSanVotes"] == "0.000000000000000000"
  end

  test "deleting a post", %{user: user, conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        link: "http://example.com",
        approved_at: Timex.now()
      }
      |> Repo.insert!()

    %Vote{post_id: sanbase_post.id, user_id: user.id}
    |> Repo.insert!()

    query = """
    mutation {
      deletePost(id: #{sanbase_post.id}) {
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    sanbasePost = json_response(result, 200)["data"]["deletePost"]

    assert sanbasePost["id"] == Integer.to_string(sanbase_post.id)
  end

  test "deleting a post which does not belong to the user", %{conn: conn} do
    other_user =
      %User{salt: User.generate_salt()}
      |> Repo.insert!()

    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: other_user.id,
        title: "Awesome analysis",
        link: "http://example.com",
        approved_at: Timex.now()
      }
      |> Repo.insert!()

    query = """
    mutation {
      deletePost(id: #{sanbase_post.id}) {
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    data = json_response(result, 200)

    assert data["errors"] != nil
    assert data["data"]["deletePost"] == nil
  end
end
