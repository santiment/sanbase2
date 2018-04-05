defmodule SanbaseWeb.Graphql.PostTest do
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

    user2 =
      %User{
        salt: User.generate_salt(),
        san_balance:
          Decimal.mult(Decimal.new("10.000000000000000000"), Ethauth.san_token_decimals()),
        san_balance_updated_at: Timex.now()
      }
      |> Repo.insert!()

    {:ok, conn: conn, user: user, user2: user2}
  end

  test "getting all posts as anon user", %{user: user} do
    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    query = """
    {
      allInsights {
        title,
        short_desc
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "allInsights"))

    assert [%{"title" => post.title, "short_desc" => post.short_desc}] ==
             json_response(result, 200)["data"]["allInsights"]
  end

  test "trying to get not allowed field from posts as anon user", %{user: user} do
    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    query = """
    {
      allInsights {
        id,
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "allInsights"))

    [error] = json_response(result, 200)["errors"]
    assert "unauthorized" == error["message"]
  end

  test "getting all posts as logged in user", %{user: user, conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    query = """
    {
      allInsights {
        id,
        title,
        short_desc,
        text,
        user {
          email
        }
        related_projects {
          ticker
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsights"))

    assert json_response(result, 200)["data"]["allInsights"] |> List.first() |> Map.get("text") ==
             post.text
  end

  test "getting all posts for given user", %{user: user, user2: user2, conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    post2 =
      %Post{
        poll_id: poll.id,
        user_id: user2.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    query = """
    {
      allInsightsForUser(user_id: #{user.id}) {
        id,
        title,
        short_desc,
        text,
        user {
          email
        }
        related_projects {
          ticker
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsightsForUser"))

    assert json_response(result, 200)["data"]["allInsightsForUser"] |> Enum.count() == 1

    assert json_response(result, 200)["data"]["allInsightsForUser"]
           |> List.first()
           |> Map.get("text") == post.text
  end

  test "getting all posts user has voted for", %{user: user, user2: user2, conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    %Vote{post_id: post.id, user_id: user.id}
    |> Repo.insert!()

    post2 =
      %Post{
        poll_id: poll.id,
        user_id: user2.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    %Vote{post_id: post2.id, user_id: user2.id}
    |> Repo.insert!()

    query = """
    {
      allInsightsUserVoted(user_id: #{user.id}) {
        id,
        title,
        short_desc,
        text,
        user {
          email
        }
        related_projects {
          ticker
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsightsUserVoted"))

    assert json_response(result, 200)["data"]["allInsightsUserVoted"] |> Enum.count() == 1

    assert json_response(result, 200)["data"]["allInsightsUserVoted"]
           |> List.first()
           |> Map.get("text") == post.text
  end
end
