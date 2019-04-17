defmodule SanbaseWeb.Graphql.PostTest do
  use SanbaseWeb.ConnCase, async: false
  use Mockery

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Tag
  alias Sanbase.Insight.{Poll, Post, Vote}
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  setup do
    poll = Poll.find_or_insert_current_poll!()
    user = insert(:staked_user, username: "user1")
    user2 = insert(:staked_user, username: "user2")

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

  test "getting a post by id", %{conn: conn, user: user, poll: poll} do
    post = insert(:post, poll: poll, user: user, state: Post.approved_state())

    query = """
    {
      post(id: #{post.id}) {
        text
      }
    }
    """

    result = conn |> post("/graphql", query_skeleton(query, "post"))

    assert json_response(result, 200)["data"]["post"] |> Map.get("text") == post.text
  end

  test "getting a post by id for anon user", %{user: user, poll: poll} do
    post = insert(:post, poll: poll, user: user, state: Post.approved_state())

    query = """
    {
      post(id: #{post.id}) {
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
      |> post("/graphql", query_skeleton(query, "post"))

    fetched_post = json_response(result, 200)["data"]["post"]
    assert fetched_post["state"] == post.state

    {:ok, created_at, 0} = DateTime.from_iso8601(fetched_post["createdAt"])

    assert Sanbase.TestUtils.date_close_to(
             Timex.now(),
             created_at,
             2,
             :seconds
           )

    {:ok, updated_at, 0} = DateTime.from_iso8601(fetched_post["updatedAt"])

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

  test "excluding draft and not approved posts from allInsights", %{
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

  test "getting all posts for given user", %{user: user, user2: user2, conn: conn, poll: poll} do
    post = insert(:post, poll: poll, user: user, ready_state: Post.published())
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

  test "getting all posts user has voted for", %{user: user, user2: user2, conn: conn, poll: poll} do
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
        id,
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

  test "Search posts by tag", %{user: user, conn: conn, poll: poll} do
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

    result =
      tag1
      |> insights_by_tag_query()
      |> execute_query(conn, "allInsightsByTag")

    assert result == [%{"id" => "#{post.id}"}]
  end

  test "Search posts by tag for anonymous user", %{user: user, poll: poll} do
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

    result =
      tag1
      |> insights_by_tag_query()
      |> execute_query(build_conn(), "allInsightsByTag")

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

    post2 =
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

    result =
      [tag1.name, tag2.name]
      |> insights_by_tags_query()
      |> execute_query(build_conn(), "allInsights")

    assert result == [%{"id" => "#{post.id}"}, %{"id" => "#{post3.id}"}]
  end

  describe "create post" do
    test "adding a new post to the current poll", %{user: user, conn: conn} do
      query = """
      mutation {
        createPost(title: "Awesome post", text: "Example body") {
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

      sanbasePost = json_response(result, 200)["data"]["createPost"]

      assert sanbasePost["id"] != nil
      assert sanbasePost["title"] == "Awesome post"
      assert sanbasePost["state"] == Post.awaiting_approval_state()
      assert sanbasePost["user"]["id"] == user.id |> Integer.to_string()
      assert sanbasePost["votes"]["totalSanVotes"] == 0
      assert sanbasePost["publishedAt"] == nil

      createdAt = Timex.parse!(sanbasePost["createdAt"], "{ISO:Extended}")

      # Assert that now() and createdAt do not differ by more than 2 seconds.
      assert Sanbase.TestUtils.date_close_to(Timex.now(), createdAt, 2, :seconds)
    end

    test "adding a new post with a very long title", %{conn: conn} do
      long_title = Stream.cycle(["a"]) |> Enum.take(200) |> Enum.join()

      query = """
      mutation {
        createPost(title: "#{long_title}", text: "This is the body of the post") {
          id,
          title
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      assert json_response(result, 200)["errors"]
    end

    test "create post with tags", %{conn: conn} do
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", coinmarketcap_id: "santiment"})
      tag = Repo.insert!(%Tag{name: "SAN"})

      mutation = """
      mutation {
        createPost(title: "Awesome post", text: "Example body", tags: ["#{tag.name}"]) {
          tags{
            name
          },
          related_projects {
            ticker
          },
          readyState
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [tag] = json_response(result, 200)["data"]["createPost"]["tags"]
      [related_projects] = json_response(result, 200)["data"]["createPost"]["related_projects"]
      readyState = json_response(result, 200)["data"]["createPost"]["readyState"]

      assert tag == %{"name" => "SAN"}
      assert related_projects == %{"ticker" => "SAN"}
      assert readyState == Post.draft()
    end

    @test_file_hash "15e9f3c52e8c7f2444c5074f3db2049707d4c9ff927a00ddb8609bfae5925399"
    test "create post with image and retrieve the image hash and url", %{conn: conn} do
      image_url = upload_image(conn)

      mutation = """
      mutation {
        createPost(title: "Awesome post", text: "Example body", imageUrls: ["#{image_url}"]) {
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

      [image] = json_response(result, 200)["data"]["createPost"]["images"]

      assert image["imageUrl"] == image_url
      assert image["contentHash"] == @test_file_hash

      # assert that the file exists
      assert true == File.exists?(image_url)
    end

    test "cannot reuse images", %{conn: conn} do
      image_url = upload_image(conn)

      mutation = """
      mutation {
        createPost(title: "Awesome post", text: "Example body", imageUrls: ["#{image_url}"]) {
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
          updatePost(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{
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

      new_post = json_response(result, 200)["data"]["updatePost"]
      assert new_post["title"] == "Awesome post2"
    end

    test "cannot update not owned post", %{conn: conn, user2: user2, poll: poll} do
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
          updatePost(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{
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
      assert String.contains?(error["message"], "Cannot update not owned post")
    end

    test "cannot update published posts", %{conn: conn, user: user, poll: poll} do
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
          updatePost(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{
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
      assert String.contains?(error["message"], "Cannot update published post")
    end
  end

  describe "delete post" do
    test "deleting a post", %{user: user, conn: conn, poll: poll} do
      sanbase_post = insert(:post, poll: poll, user: user, state: Post.approved_state())

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

    test "deleting a post which does not belong to the user - returns error", %{
      conn: conn,
      user2: user2,
      poll: poll
    } do
      sanbase_post = insert(:post, poll: poll, user: user2, state: Post.approved_state())

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

  describe "publish post" do
    @discourse_response_file "#{File.cwd!()}/test/sanbase_web/graphql/assets/discourse_publish_response.json"
    test "publish post", %{user: user, conn: conn, poll: poll} do
      mock(
        Sanbase.Discourse.Api,
        :publish,
        @discourse_response_file |> File.read!() |> Jason.decode()
      )

      mock(Sanbase.Notifications.Insight, :publish_in_discord, :ok)

      post =
        insert(:post,
          poll: poll,
          user: user,
          state: Post.approved_state(),
          ready_state: Post.draft()
        )

      query = """
      mutation {
        publishInsight(id: #{post.id}) {
          id,
          readyState,
          discourseTopicUrl
          publishedAt
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      insight = json_response(result, 200)["data"]["publishInsight"]
      published_at = insight["publishedAt"] |> Sanbase.DateTimeUtils.from_iso8601!()

      # Test that the published_at time is set to almost now
      assert abs(Timex.diff(Timex.now(), published_at, :seconds)) < 2
      assert insight["readyState"] == Post.published()

      assert insight["discourseTopicUrl"] ==
               "https://discourse.stage.internal.santiment.net/t/first-test-from-api2/234"
    end

    test "publish post returns error when user is not author", %{
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

      query = """
      mutation {
        publishInsight(id: #{post.id}) {
          id,
          ready_state
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(query))

      assert json_response(result, 200)["errors"]
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

  # Helper functions

  @test_file_path "#{File.cwd!()}/test/sanbase_web/graphql/assets/image.png"
  defp upload_image(conn) do
    mutation = """
      mutation {
        uploadImage(images: ["img"]){
          fileName
          contentHash,
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

    [imageData] = json_response(result, 200)["data"]["uploadImage"]
    imageData["imageUrl"]
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

  defp execute_query(query, conn, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> get_in(["data", query_name])
  end
end
