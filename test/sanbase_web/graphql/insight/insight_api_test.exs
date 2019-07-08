defmodule SanbaseWeb.Graphql.InsightApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import ExUnit.CaptureLog
  import Sanbase.TestHelpers

  alias Sanbase.Tag
  alias Sanbase.Insight.{Poll, Post, Vote}
  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent

  setup do
    clean_task_supervisor_children()

    poll = Poll.find_or_insert_current_poll!()
    user = insert(:staked_user)
    user2 = insert(:staked_user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, user2: user2, poll: poll}
  end

  test "getting all inisghts for currentUser", %{conn: conn, user: user, poll: poll} do
    published =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    draft =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.draft()
      )

    query = """
    {
      currentUser {
        insights {
          id,
          text,
          readyState
        }
      }
    }
    """

    result = conn |> post("/graphql", query_skeleton(query, "currentUser"))

    assert json_response(result, 200)["data"]["currentUser"] == %{
             "insights" => [
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
           }
  end

  test "get an insight by id", %{conn: conn, user: user, poll: poll} do
    post = insert(:post, poll: poll, user: user, state: Post.approved_state())

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

  test "getting an insight by id for anon user", %{user: user, poll: poll} do
    post = insert(:post, poll: poll, user: user, state: Post.approved_state())

    query = """
    {
      insight(id: #{post.id}) {
        id,
        title,
        shortDesc,
        state,
        createdAt,
        updatedAt,
        user {
          id,
          username
        },
        votes{
          totalSanVotes
        }
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "insight"))

    fetched_insight = json_response(result, 200)["data"]["insight"]
    assert fetched_insight["state"] == post.state

    {:ok, created_at, 0} = DateTime.from_iso8601(fetched_insight["createdAt"])

    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             created_at,
             2,
             :seconds
           )

    {:ok, updated_at, 0} = DateTime.from_iso8601(fetched_insight["updatedAt"])

    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             updated_at,
             2,
             :seconds
           )
  end

  test "getting all posts as anon user", %{user: user, poll: poll} do
    post =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published()
      )

    query = """
    {
      allInsights {
        title,
        shortDesc,
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
               "shortDesc" => post.short_desc,
               "readyState" => Post.published()
             }
           ] == json_response(result, 200)["data"]["allInsights"]
  end

  test "excluding draft and not approved insights from allInsights", %{
    conn: conn,
    poll: poll,
    user: user,
    user2: user2
  } do
    insert(:post,
      poll: poll,
      user: user,
      state: Post.approved_state(),
      ready_state: Post.published()
    )

    insert(:post,
      poll: poll,
      user: user,
      state: Post.awaiting_approval_state(),
      ready_state: Post.published()
    )

    insert(:post, poll: poll, user: user, state: Post.approved_state(), ready_state: Post.draft())

    insert(:post,
      poll: poll,
      user: user2,
      state: Post.approved_state(),
      ready_state: Post.published()
    )

    query = """
    {
      allInsights {
        id,
        text,
        readyState
      }
    }
    """

    result = conn |> post("/graphql", query_skeleton(query, "allInsights"))

    assert json_response(result, 200)["data"]["allInsights"] |> length() == 2
  end

  test "getting all insight for given user", %{user: user, user2: user2, conn: conn, poll: poll} do
    post =
      insert(:post,
        poll: poll,
        user: user,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    insert(:post, poll: poll, user: user, ready_state: Post.draft())
    insert(:post, poll: poll, user: user2, ready_state: Post.published())

    query = """
    {
      allInsightsForUser(user_id: #{user.id}) {
        id,
        text
      }
    }
    """

    all_insights_for_user =
      conn
      |> post("/graphql", query_skeleton(query, "allInsightsForUser"))
      |> json_response(200)
      |> get_in(["data", "allInsightsForUser"])

    assert all_insights_for_user |> Enum.count() == 1
    assert all_insights_for_user |> hd() |> Map.get("text") == post.text
  end

  test "getting all insight user has voted for", %{
    user: user,
    user2: user2,
    conn: conn,
    poll: poll
  } do
    post =
      insert(:post,
        poll: poll,
        user: user,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    post2 =
      insert(:post,
        poll: poll,
        user: user2,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    %Vote{post_id: post.id, user_id: user.id}
    |> Repo.insert!()

    %Vote{post_id: post2.id, user_id: user2.id}
    |> Repo.insert!()

    query = """
    {
      allInsightsUserVoted(user_id: #{user.id}) {
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

  test "getting all insights ordered", %{user: user, user2: user2, conn: conn, poll: poll} do
    post =
      insert(:post,
        poll: poll,
        user: user,
        ready_state: Post.published(),
        state: Post.approved_state(),
        published_at: Timex.now() |> Timex.shift(seconds: -10)
      )

    %Vote{}
    |> Vote.changeset(%{post_id: post.id, user_id: user.id})
    |> Repo.insert!()

    post2 =
      insert(:post,
        poll: poll,
        user: user2,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    %Vote{post_id: post2.id, user_id: user.id}
    |> Repo.insert!()

    %Vote{post_id: post2.id, user_id: user2.id}
    |> Repo.insert!()

    query = """
    {
      allInsights {
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsights"))

    Repo.all(Post)

    assert json_response(result, 200)["data"]["allInsights"] ==
             [%{"id" => "#{post2.id}"}, %{"id" => "#{post.id}"}]
  end

  test "Search insights by tag", %{user: user, conn: conn, poll: poll} do
    tag1 = insert(:tag, name: "PRJ1")
    tag2 = insert(:tag, name: "PRJ2")

    post =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag1, tag2]
      )

    result = execute_query(conn, insights_by_tag_query(tag1), "allInsightsByTag")

    assert result == [%{"id" => "#{post.id}"}]
  end

  test "Search insights by tag for anonymous user", %{user: user, poll: poll} do
    tag1 = insert(:tag, name: "PRJ1")
    tag2 = insert(:tag, name: "PRJ2")

    post =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag1, tag2]
      )

    result = execute_query(build_conn(), insights_by_tag_query(tag1), "allInsightsByTag")

    assert result == [%{"id" => "#{post.id}"}]
  end

  test "Get all insights by a list of tags", %{user: user, poll: poll} do
    tag1 = insert(:tag, name: "PRJ1")
    tag2 = insert(:tag, name: "PRJ2")
    tag3 = insert(:tag, name: "PRJ3")

    post =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag1, tag2]
      )

    insert(:post,
      poll: poll,
      user: user,
      state: Post.approved_state(),
      ready_state: Post.published(),
      tags: [tag3]
    )

    post3 =
      insert(:post,
        poll: poll,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag2]
      )

    query = insights_by_tags_query([tag1.name, tag2.name])
    result = execute_query(build_conn(), query, "allInsights")

    assert result == [%{"id" => "#{post.id}"}, %{"id" => "#{post3.id}"}]
  end

  describe "create insight" do
    test "adding a new insight to the current poll", %{user: user, conn: conn} do
      query = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body") {
          id,
          title,
          text,
          user {
            id
          },
          votes{
            totalSanVotes,
          }
          state,
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
      assert insight["votes"]["totalSanVotes"] == 0
      assert insight["publishedAt"] == nil

      created_at = Timex.parse!(insight["createdAt"], "{ISO:Extended}")

      # Assert that now() and created_at do not differ by more than 2 seconds.
      assert Sanbase.TestUtils.date_close_to(Timex.now(), created_at, 2, :seconds)
    end

    test "adding a new insight with a very long title", %{conn: conn} do
      long_title = Stream.cycle(["a"]) |> Enum.take(200) |> Enum.join()

      query = """
      mutation {
        createInsight(title: "#{long_title}", text: "This is the body of the insight") {
          id
          title
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      assert json_response(result, 200)["errors"]
    end

    test "create insight with tags", %{conn: conn} do
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})
      tag = Repo.insert!(%Tag{name: "SAN"})

      mutation = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body", tags: ["#{tag.name}"]) {
          tags{
            name
          }
          relatedProjects {
            ticker
          }
          readyState
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [tag] = json_response(result, 200)["data"]["createInsight"]["tags"]
      [related_projects] = json_response(result, 200)["data"]["createInsight"]["relatedProjects"]
      readyState = json_response(result, 200)["data"]["createInsight"]["readyState"]

      assert tag == %{"name" => "SAN"}
      assert related_projects == %{"ticker" => "SAN"}
      assert readyState == Post.draft()
    end

    @test_file_hash "15e9f3c52e8c7f2444c5074f3db2049707d4c9ff927a00ddb8609bfae5925399"
    test "create an insight with image and retrieve the image hash and url", %{conn: conn} do
      image_url = upload_image(conn)

      mutation = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body", imageUrls: ["#{image_url}"]) {
          images{
            imageUrl
            contentHash
          }
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [image] = json_response(result, 200)["data"]["createInsight"]["images"]

      assert image["imageUrl"] == image_url
      assert image["contentHash"] == @test_file_hash

      # assert that the file exists
      assert true == File.exists?(image_url)
    end

    test "cannot reuse images", %{conn: conn} do
      image_url = upload_image(conn)

      mutation = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body", imageUrls: ["#{image_url}"]) {
          images{
            imageUrl
            contentHash
          }
        }
      }
      """

      _ =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      result2 =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [error] = json_response(result2, 200)["errors"]
      assert String.contains?(error["details"]["images"] |> hd, "already used")
    end
  end

  describe "update post" do
    test "update post", %{conn: conn, user: user} do
      image_url = upload_image(conn)
      poll = Poll.find_or_insert_current_poll!()
      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          poll: poll,
          user: user,
          ready_state: Post.draft(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{
        tag2.name
      }"], imageUrls: ["#{image_url}"]) {
            id
            title
            text
            images{
              imageUrl
              contentHash
            }
            tags {
              name
            }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      new_post = json_response(result, 200)["data"]["updateInsight"]
      assert new_post["title"] == "Awesome post2"
    end

    test "cannot update not owned insight", %{conn: conn, user2: user2, poll: poll} do
      image_url = upload_image(conn)
      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          poll: poll,
          user: user2,
          ready_state: Post.draft(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{
        tag2.name
      }"], imageUrls: ["#{image_url}"]) {
            id,
            title,
            text,
            images{
              imageUrl
              contentHash
            }
            tags {
              name
            }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [error] = json_response(result, 200)["errors"]
      assert String.contains?(error["message"], "Cannot update not owned insight")
    end

    test "cannot update published insights", %{conn: conn, user: user, poll: poll} do
      image_url = upload_image(conn)

      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          poll: poll,
          user: user,
          ready_state: Post.published(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{
        tag2.name
      }"], imageUrls: ["#{image_url}"]) {
            id,
            title,
            text,
            images{
              imageUrl
              contentHash
            }
            tags {
              name
            }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [error] = json_response(result, 200)["errors"]
      assert String.contains?(error["message"], "Cannot update published insight")
    end
  end

  describe "delete post" do
    test "deleting a post", %{user: user, conn: conn, poll: poll} do
      sanbase_post = insert(:post, poll: poll, user: user, state: Post.approved_state())

      %Vote{post_id: sanbase_post.id, user_id: user.id}
      |> Repo.insert!()

      query = """
      mutation {
        deleteInsight(id: #{sanbase_post.id}) {
          id
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      sanbasePost = json_response(result, 200)["data"]["deleteInsight"]

      assert sanbasePost["id"] == Integer.to_string(sanbase_post.id)
    end

    test "deleting an insight which does not belong to the user - returns error", %{
      conn: conn,
      user2: user2,
      poll: poll
    } do
      sanbase_post = insert(:post, poll: poll, user: user2, state: Post.approved_state())

      query = """
      mutation {
        deleteInsight(id: #{sanbase_post.id}) {
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

  describe "publish post" do
    @discourse_response_file "#{File.cwd!()}/test/sanbase_web/graphql/assets/discourse_publish_response.json"
    test "successfully publishes in Discourse and Discord and creates timeline event", %{
      user: user,
      conn: conn,
      poll: poll
    } do
      with_mocks([
        {Sanbase.Discourse.Api, [],
         [publish: fn _, _ -> @discourse_response_file |> File.read!() |> Jason.decode() end]},
        {Sanbase.Notifications.Insight, [], [publish_in_discord: fn _ -> :ok end]}
      ]) do
        post =
          insert(:post,
            poll: poll,
            user: user,
            state: Post.approved_state(),
            ready_state: Post.draft()
          )

        result =
          post
          |> publish_insight_mutation()
          |> execute_mutation_with_success("publishInsight", conn)

        assert_receive({_, {:ok, %TimelineEvent{}}})

        assert result["readyState"] == Post.published()

        assert result["discourseTopicUrl"] ==
                 "https://discourse.stage.internal.santiment.net/t/first-test-from-api2/234"

        assert result["publishedAt"] != nil

        assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 1
      end
    end

    test "returns error when insight does not exist with the provided post_id", %{conn: conn} do
      result =
        %{id: 1000}
        |> publish_insight_mutation()
        |> execute_mutation_with_errors(conn)

      assert String.contains?(result["message"], "Cannot publish insight with id 1000")
    end

    test "returns error when discourse publish fails", %{user: user, conn: conn, poll: poll} do
      with_mocks([
        {Sanbase.Discourse.Api, [],
         [publish: fn _, _ -> {:error, "Cannot publish to discourse"} end]},
        {Sanbase.Notifications.Insight, [], [publish_in_discord: fn _ -> :ok end]}
      ]) do
        post =
          insert(:post,
            poll: poll,
            user: user,
            state: Post.approved_state(),
            ready_state: Post.draft()
          )

        capture_log(fn ->
          result =
            post
            |> publish_insight_mutation()
            |> execute_mutation_with_errors(conn)

          assert String.contains?(result["message"], "Cannot publish insight")
        end)
      end
    end

    @discourse_response_file "#{File.cwd!()}/test/sanbase_web/graphql/assets/discourse_publish_response.json"
    test "still returns post when discord publish fails", %{user: user, conn: conn, poll: poll} do
      with_mocks([
        {Sanbase.Discourse.Api, [],
         [publish: fn _, _ -> @discourse_response_file |> File.read!() |> Jason.decode() end]},
        {Sanbase.Notifications.Insight, [],
         [publish_in_discord: fn _ -> {:error, "Error publishing in discord"} end]}
      ]) do
        post =
          insert(:post,
            poll: poll,
            user: user,
            state: Post.approved_state(),
            ready_state: Post.draft()
          )

        result =
          post
          |> publish_insight_mutation()
          |> execute_mutation_with_success("publishInsight", conn)

        assert_receive({_, {:ok, %TimelineEvent{}}})

        assert result["readyState"] == Post.published()
      end
    end

    test "returns error when user is not author", %{
      conn: conn,
      poll: poll,
      user2: user2
    } do
      post =
        insert(:post,
          poll: poll,
          user: user2,
          state: Post.approved_state(),
          ready_state: Post.draft()
        )

      result =
        post
        |> publish_insight_mutation()
        |> execute_mutation_with_errors(conn)

      assert String.contains?(result["message"], "Cannot publish not own insight")
    end

    test "returns error when insight is already published", %{
      conn: conn,
      poll: poll,
      user: user
    } do
      post =
        insert(:post,
          poll: poll,
          user: user,
          state: Post.approved_state(),
          ready_state: Post.published()
        )

      result =
        post
        |> publish_insight_mutation()
        |> execute_mutation_with_errors(conn)

      assert String.contains?(result["message"], "Cannot publish already published insight")
    end
  end

  test "get all tags", %{conn: conn} do
    tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
    tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

    query = """
    {
      allTags {
        name
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allTags"))

    assert json_response(result, 200)["data"]["allTags"] ==
             [%{"name" => tag1.name}, %{"name" => tag2.name}]
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
        id
        votes{
          totalSanVotes
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    sanbasePost = json_response(result, 200)["data"]["vote"]

    assert sanbasePost["id"] == Integer.to_string(sanbase_post.id)

    assert sanbasePost["votes"]["totalSanVotes"] == Decimal.to_integer(user.san_balance)
  end

  test "unvoting an insight", %{conn: conn, user: user} do
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
      unvote(insightId: #{sanbase_post.id}) {
        id
        votes{
          totalSanVotes
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    result_post = json_response(result, 200)["data"]["unvote"]

    assert result_post["id"] == Integer.to_string(sanbase_post.id)
    assert result_post["votes"]["totalSanVotes"] == 0
  end

  # Helper functions

  defp publish_insight_mutation(post) do
    """
    mutation {
      publishInsight(id: #{post.id}) {
        id
        readyState
        discourseTopicUrl
        publishedAt
      }
    }
    """
  end

  defp execute_mutation_with_success(query, query_name, conn) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> get_in(["data", query_name])
  end

  defp execute_mutation_with_errors(query, conn) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
  end

  @test_file_path "#{File.cwd!()}/test/sanbase_web/graphql/assets/image.png"
  defp upload_image(conn) do
    mutation = """
      mutation {
        uploadImage(images: ["img"]){
          fileName
          contentHash
          imageUrl
        }
      }
    """

    upload = %Plug.Upload{
      content_type: "application/octet-stream",
      filename: "image.png",
      path: @test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img" => upload})

    [image_data] = json_response(result, 200)["data"]["uploadImage"]
    image_data["imageUrl"]
  end

  defp insights_by_tag_query(tag) do
    """
    {
      allInsightsByTag(tag: "#{tag.name}"){
        id
      }
    }
    """
  end

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
