defmodule SanbaseWeb.Graphql.PulseInsightApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Tag
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    staked_user = insert(:staked_user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, staked_user: staked_user}
  end

  test "getting all pulse inisghts for currentUser", %{conn: conn, user: user} do
    _ignored_non_pulse =
      insert(:post, user: user, state: Post.approved_state(), ready_state: Post.published())

    published =
      insert(:post,
        user: user,
        is_pulse: true,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    draft =
      insert(:post,
        user: user,
        is_pulse: true,
        state: Post.approved_state(),
        ready_state: Post.draft()
      )

    query = """
    {
      currentUser {
        insights(isPulse: true) {
          id
          text
          readyState
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "currentUser"))
      |> json_response(200)

    expected_insights =
      [
        %{
          "id" => "#{published.id}",
          "readyState" => "#{published.ready_state}",
          "text" => "#{published.text}"
        },
        %{
          "id" => "#{draft.id}",
          "readyState" => "#{draft.ready_state}",
          "text" => "#{draft.text}"
        }
      ]
      |> Enum.sort_by(& &1["id"])

    insights = result["data"]["currentUser"]["insights"] |> Enum.sort_by(& &1["id"])

    assert insights == expected_insights
  end

  test "get pulse insight by id", %{conn: conn, user: user} do
    _ignored_non_pulse = insert(:post, user: user, state: Post.approved_state())
    post = insert(:post, user: user, is_pulse: true, state: Post.approved_state())

    query = """
    {
      insight(id: #{post.id}) {
        text
      }
    }
    """

    result = conn |> post("/graphql", query_skeleton(query, "post"))

    assert json_response(result, 200)["data"]["insight"] |> Map.get("text") == post.text
  end

  test "getting pulse insight by id for anon user", %{user: user} do
    _ignored_non_pulse = insert(:post, user: user, state: Post.approved_state())
    post = insert(:post, user: user, is_pulse: true, state: Post.approved_state())

    query = """
    {
      insight(id: #{post.id}) {
        state,
        createdAt
        updatedAt
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "insight"))

    fetched_insight = json_response(result, 200)["data"]["insight"]
    assert fetched_insight["state"] == post.state

    created_at = Sanbase.DateTimeUtils.from_iso8601!(fetched_insight["createdAt"])

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             created_at,
             2,
             :seconds
           )

    updated_at = Sanbase.DateTimeUtils.from_iso8601!(fetched_insight["updatedAt"])

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             updated_at,
             2,
             :seconds
           )
  end

  test "getting all pulse insights as anon user", %{user: user} do
    _ignored_non_pulse =
      insert(:post, user: user, state: Post.approved_state(), ready_state: Post.published())

    post =
      insert(:post,
        user: user,
        is_pulse: true,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    query = """
    {
      allInsights(isPulse: true) {
        title
        readyState
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "allInsights"))

    assert [
             %{
               "title" => post.title,
               "readyState" => Post.published()
             }
           ] == json_response(result, 200)["data"]["allInsights"]
  end

  test "excluding draft and not approved pulse insights from allInsights", %{
    conn: conn,
    user: user,
    staked_user: staked_user
  } do
    insert(:post,
      user: user,
      is_pulse: true,
      state: Post.approved_state(),
      ready_state: Post.published()
    )

    insert(:post,
      user: user,
      is_pulse: true,
      state: Post.awaiting_approval_state(),
      ready_state: Post.published()
    )

    insert(:post,
      user: user,
      is_pulse: true,
      state: Post.approved_state(),
      ready_state: Post.draft()
    )

    insert(:post,
      user: staked_user,
      is_pulse: true,
      state: Post.approved_state(),
      ready_state: Post.published()
    )

    query = """
    {
      allInsights(isPulse: true) {
        id
      }
    }
    """

    result = conn |> post("/graphql", query_skeleton(query, "allInsights"))

    assert json_response(result, 200)["data"]["allInsights"] |> length() == 2
  end

  test "getting all pulse insight for given user", context do
    %{user: user, staked_user: staked_user, conn: conn} = context

    _ignored_non_pulse =
      insert(:post, user: user, state: Post.approved_state(), ready_state: Post.published())

    post =
      insert(:post,
        user: user,
        is_pulse: true,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    insert(:post, user: user, is_pulse: true, ready_state: Post.draft())
    insert(:post, user: staked_user, is_pulse: true, ready_state: Post.published())

    query = """
    {
      allInsightsForUser(user_id: #{user.id}, isPulse: true) {
        id
        title
      }
    }
    """

    all_insights_for_user =
      conn
      |> post("/graphql", query_skeleton(query, "allInsightsForUser"))
      |> json_response(200)
      |> get_in(["data", "allInsightsForUser"])

    assert all_insights_for_user |> length() == 1
    assert all_insights_for_user |> hd() |> Map.get("title") == post.title
  end

  test "getting all pulse insight user has voted for", context do
    %{user: user, staked_user: staked_user, conn: conn} = context

    post =
      insert(:post,
        user: user,
        is_pulse: true,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    post2 =
      insert(:post,
        user: staked_user,
        is_pulse: true,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    Vote.create(%{post_id: post.id, user_id: user.id})
    Vote.create(%{post_id: post2.id, user_id: staked_user.id})

    query = """
    {
      allInsightsUserVoted(user_id: #{user.id}, isPulse: true) {
        id,
        text
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsightsUserVoted"))
      |> json_response(200)
      |> get_in(["data", "allInsightsUserVoted"])

    assert result |> Enum.count() == 1
    assert result |> hd() |> Map.get("text") == post.text
  end

  test "get all insights by a list of tags", %{user: user} do
    tag1 = insert(:tag, name: "PRJ1")
    tag2 = insert(:tag, name: "PRJ2")
    tag3 = insert(:tag, name: "PRJ3")

    post =
      insert(:post,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag1, tag2]
      )

    insert(:post,
      user: user,
      state: Post.approved_state(),
      ready_state: Post.published(),
      tags: [tag3]
    )

    post3 =
      insert(:post,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag2]
      )

    query = insights_by_tags_query([tag1.name, tag2.name])
    result = execute_query(build_conn(), query, "allInsights") |> Enum.sort_by(& &1["id"])

    assert result ==
             [%{"id" => "#{post.id}"}, %{"id" => "#{post3.id}"}] |> Enum.sort_by(& &1["id"])
  end

  describe "create pulse insight" do
    test "adding a new pulse insight", %{user: user, conn: conn} do
      query = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body", isPulse: true) {
          id
          title
          text
          user { id }
          votes{ totalVotes }
          state
          createdAt
          publishedAt
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      insight = json_response(result, 200)["data"]["createInsight"]

      assert insight["id"] != nil
      assert insight["title"] == "Awesome post"
      assert insight["state"] == Post.approved_state()
      assert insight["user"]["id"] == user.id |> Integer.to_string()
      assert insight["votes"]["totalVotes"] == 0
      assert insight["publishedAt"] == nil

      created_at = Timex.parse!(insight["createdAt"], "{ISO:Extended}")

      # Assert that now() and created_at do not differ by more than 2 seconds.
      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), created_at, 2, :seconds)
    end

    test "create pulse insight with tags", %{conn: conn} do
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", slug: "santiment"})
      tag = Repo.insert!(%Tag{name: "SAN"})

      mutation = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body", tags: ["#{tag.name}"], isPulse: true) {
          tags{ name }
          relatedProjects { ticker }
          readyState
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [tag] = json_response(result, 200)["data"]["createInsight"]["tags"]
      [related_projects] = json_response(result, 200)["data"]["createInsight"]["relatedProjects"]
      ready_state = json_response(result, 200)["data"]["createInsight"]["readyState"]

      assert tag == %{"name" => "SAN"}
      assert related_projects == %{"ticker" => "SAN"}
      assert ready_state == Post.draft()
    end
  end

  describe "update pulse insight" do
    test "update pulse insight", %{conn: conn, user: user} do
      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          user: user,
          is_pulse: true,
          ready_state: Post.draft(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(
            id: #{post.id}
            title: "Awesome post2"
            text: "Example body2"
            tags: ["#{tag2.name}"]) {
              id
              title
              text
              tags { name }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      new_post = json_response(result, 200)["data"]["updateInsight"]
      assert new_post["title"] == "Awesome post2"
    end

    test "cannot update not owned pulse insight", %{conn: conn, staked_user: staked_user} do
      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          is_pulse: true,
          user: staked_user,
          ready_state: Post.draft(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(
            id: #{post.id}
            title: "Awesome post2"
            text: "Example body2"
            tags: ["#{tag2.name}"]) {
              id
              title
              text
              tags { name }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [error] = json_response(result, 200)["errors"]
      assert String.contains?(error["message"], "Cannot update not owned insight")
    end
  end

  # Helper functions

  defp insights_by_tags_query(tags) do
    """
    {
      allInsights(tags: #{Jason.encode!(tags)}){
        id
      }
    }
    """
  end
end
