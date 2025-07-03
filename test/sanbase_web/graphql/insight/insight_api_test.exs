defmodule SanbaseWeb.Graphql.InsightApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Tag
  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.Project
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    staked_user = insert(:staked_user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, staked_user: staked_user}
  end

  describe "Insight creation rate limit" do
    setup do
      # on exit revert to the original test env that is higher than
      # on prod so we avoid hitting rate limits
      env = Application.get_env(:sanbase, Sanbase.Insight.Post)

      on_exit(fn -> Application.put_env(:sanbase, Sanbase.Insight.Post, env) end)

      []
    end

    test "creation rate limit per minute is enforced", context do
      query = """
      mutation { createInsight( title: "title" text: "text") { id } }
      """

      env = Application.get_env(:sanbase, Sanbase.Insight.Post)
      env = Keyword.put(env, :creation_limit_minute, 2)
      Application.put_env(:sanbase, Sanbase.Insight.Post, env)

      _ = execute_mutation_with_success(query, "createInsight", context.conn)
      _ = execute_mutation_with_success(query, "createInsight", context.conn)

      error = execute_mutation_with_errors(query, context.conn)
      assert error["message"] =~ "Cannot create more than 2 insights per minute"
    end

    test "creation rate limit per hour is enforced", context do
      query = """
      mutation { createInsight( title: "title" text: "text") { id } }
      """

      env = Application.get_env(:sanbase, Sanbase.Insight.Post)
      env = Keyword.put(env, :creation_limit_hour, 1)
      Application.put_env(:sanbase, Sanbase.Insight.Post, env)

      _ = execute_mutation_with_success(query, "createInsight", context.conn)

      error = execute_mutation_with_errors(query, context.conn)
      assert error["message"] =~ "Cannot create more than 1 insight per hour"
    end

    test "creation rate limit per day is enforced", context do
      query = """
      mutation { createInsight( title: "title" text: "text") { id } }
      """

      env = Application.get_env(:sanbase, Sanbase.Insight.Post)
      env = Keyword.put(env, :creation_limit_day, 1)
      Application.put_env(:sanbase, Sanbase.Insight.Post, env)

      _ = execute_mutation_with_success(query, "createInsight", context.conn)

      error = execute_mutation_with_errors(query, context.conn)
      assert error["message"] =~ "Cannot create more than 1 insight per day"
    end
  end

  describe "Insights for currentUser or getUser" do
    setup context do
      published =
        insert(:post,
          user: context.user,
          state: Post.approved_state(),
          ready_state: Post.published()
        )

      draft =
        insert(:post,
          user: context.user,
          state: Post.approved_state(),
          ready_state: Post.draft()
        )

      {:ok, published: published, draft: draft}
    end

    test "Fetching all inisghts", %{published: published, draft: draft} = context do
      query = """
      {
        currentUser {
          insights {
            id,
            text
            pulseText
            readyState
          }
        }
      }
      """

      result = execute_query(context.conn, query, "currentUser")

      expected_insights =
        [
          %{
            "id" => published.id,
            "readyState" => "#{published.ready_state}",
            "text" => "#{published.text}",
            "pulseText" => nil
          },
          %{
            "id" => draft.id,
            "readyState" => "#{draft.ready_state}",
            "text" => "#{draft.text}",
            "pulseText" => nil
          }
        ]
        |> Enum.sort_by(& &1["id"])

      insights = result["insights"] |> Enum.sort_by(& &1["id"])

      assert insights == expected_insights
    end

    test "Fetching insights count for current user", context do
      query = """
      {
        currentUser {
          insightsCount {
            totalCount
            draftCount
          }
        }
      }
      """

      result = execute_query(context.conn, query, "currentUser")
      assert result["insightsCount"]["totalCount"] == 1
      assert result["insightsCount"]["draftCount"] == 1
    end

    test "Fetching insights count for public user", context do
      query = """
      {
        getUser(selector: { id: #{context.user.id} }) {
          insightsCount {
            totalCount
          }
        }
      }
      """

      result = execute_query(context.conn, query, "getUser")
      assert result["insightsCount"]["totalCount"] == 1
    end

    test "Fetching all public inisghts", %{published: published} = context do
      query = """
      {
        getUser(selector: { id: #{context.user.id} }) {
          insights {
            id,
            text,
            readyState
          }
        }
      }
      """

      result = execute_query(context.conn, query, "getUser")

      expected_insights =
        [
          %{
            "id" => published.id,
            "readyState" => "#{published.ready_state}",
            "text" => "#{published.text}"
          }
        ]
        |> Enum.sort_by(& &1["id"])

      insights = result["insights"] |> Enum.sort_by(& &1["id"])

      assert insights == expected_insights
    end

    test "Fetching all inisghts paginated", context do
      query = """
      {
        currentUser {
          insights(page: 1, page_size: 1) {
            id,
            text,
            readyState
          }
        }
      }
      """

      result = execute_query(context.conn, query, "currentUser")
      assert length(result["insights"]) == 1
    end

    test "Fetching all public insights paginated", context do
      query = """
      {
        getUser(selector: { id: #{context.user.id} }) {
          insights(page: 2, page_size: 1) {
            id,
            text,
            readyState
          }
        }
      }
      """

      result = execute_query(context.conn, query, "getUser")
      assert result["insights"] == []
    end
  end

  test "Get an insight by id", %{conn: conn, user: user} do
    post =
      insert(:post,
        text: "test123",
        user: user,
        state: Post.approved_state()
      )

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

  test "Getting an insight by id for anon user", %{user: user} do
    post = insert(:post, user: user, state: Post.approved_state())

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
        }
        votes{
          totalVotes
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

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             created_at,
             2,
             :seconds
           )

    {:ok, updated_at, 0} = DateTime.from_iso8601(fetched_insight["updatedAt"])

    assert Sanbase.TestUtils.datetime_close_to(
             Timex.now(),
             updated_at,
             2,
             :seconds
           )
  end

  test "Getting all insights as anon user", %{user: user} do
    post =
      insert(:post,
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

  test "Excluding draft and not approved insights from allInsights", %{
    conn: conn,
    user: user,
    staked_user: staked_user
  } do
    insert(:post,
      user: user,
      state: Post.approved_state(),
      ready_state: Post.published()
    )

    insert(:post,
      user: user,
      state: Post.awaiting_approval_state(),
      ready_state: Post.published()
    )

    insert(:post, user: user, state: Post.approved_state(), ready_state: Post.draft())

    insert(:post,
      user: staked_user,
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

  test "Getting all insight for given user, paginated", %{
    user: user,
    staked_user: staked_user,
    conn: conn
  } do
    insert(:post,
      user: user,
      ready_state: Post.published(),
      state: Post.approved_state(),
      published_at: Timex.shift(Timex.now(), hours: -1)
    )

    post2 =
      insert(:post,
        user: user,
        ready_state: Post.published(),
        state: Post.approved_state(),
        published_at: Timex.now()
      )

    insert(:post, user: user, ready_state: Post.draft())
    insert(:post, user: staked_user, ready_state: Post.published())

    query = """
    {
      allInsightsForUser(user_id: #{user.id}, page: 1, page_size: 1) {
        id,
        text
      }
    }
    """

    all_insights_for_user = execute_query(conn, query, "allInsightsForUser")

    assert all_insights_for_user |> Enum.count() == 1
    assert all_insights_for_user |> hd() |> Map.get("text") == post2.text
  end

  test "Getting all insight user has voted for", %{
    user: user,
    staked_user: staked_user,
    conn: conn
  } do
    post =
      insert(:post,
        user: user,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    post2 =
      insert(:post,
        user: staked_user,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    Vote.create(%{post_id: post.id, user_id: user.id})

    Vote.create(%{post_id: post2.id, user_id: staked_user.id})

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

  test "Getting all insights ordered", %{
    user: user,
    staked_user: staked_user,
    conn: conn
  } do
    post =
      insert(:post,
        user: user,
        ready_state: Post.published(),
        state: Post.approved_state(),
        published_at: Timex.now() |> Timex.shift(seconds: -10)
      )

    Vote.create(%{post_id: post.id, user_id: user.id})

    post2 =
      insert(:post,
        user: staked_user,
        ready_state: Post.published(),
        state: Post.approved_state()
      )

    Vote.create(%{post_id: post2.id, user_id: user.id})

    Vote.create(%{post_id: post2.id, user_id: staked_user.id})

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
             [%{"id" => post2.id}, %{"id" => post.id}]
  end

  test "Search insights by tag", %{user: user, conn: conn} do
    tag1 = insert(:tag, name: "PRJ1")
    tag2 = insert(:tag, name: "PRJ2")

    post =
      insert(:post,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag1, tag2]
      )

    result = execute_query(conn, insights_by_tag_query(tag1), "allInsightsByTag")

    assert result == [%{"id" => post.id}]
  end

  test "Search insights by tag for anonymous user", %{user: user} do
    tag1 = insert(:tag, name: "PRJ1")
    tag2 = insert(:tag, name: "PRJ2")

    post =
      insert(:post,
        user: user,
        state: Post.approved_state(),
        ready_state: Post.published(),
        tags: [tag1, tag2]
      )

    result = execute_query(build_conn(), insights_by_tag_query(tag1), "allInsightsByTag")

    assert result == [%{"id" => post.id}]
  end

  test "Get all insights by a list of tags", %{user: user} do
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
             [%{"id" => post.id}, %{"id" => post3.id}] |> Enum.sort_by(& &1["id"])
  end

  describe "Create insight" do
    test "adding a new insight", %{user: user, conn: conn} do
      project = insert(:random_project)
      # Insert the metrics otherwise they cannot be added to the post
      insert(:metric_postgres, name: "daily_active_addresses")
      insert(:metric_postgres, name: "price_usd")
      insert(:metric_postgres, name: "volume_usd")

      query = """
      mutation {
        createInsight(
          title: "Awesome post"
          text: "Example body"
          metrics: ["daily_active_addresses", "price_usd", "volume_usd"]
          prediction: "heavy_bullish"
          priceChartProjectId: #{project.id}) {
            id
            title
            text
            user { id }
            votes{ totalVotes }
            state
            prediction
            priceChartProject{ id slug }
            metrics{ name }
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
      assert insight["prediction"] == "heavy_bullish"

      assert %{"name" => "daily_active_addresses"} in insight["metrics"]
      assert %{"name" => "price_usd"} in insight["metrics"]
      assert %{"name" => "volume_usd"} in insight["metrics"]

      assert insight["priceChartProject"]["id"] |> String.to_integer() == project.id
      assert insight["user"]["id"] == user.id |> Integer.to_string()
      assert insight["votes"]["totalVotes"] == 0
      assert insight["publishedAt"] == nil

      created_at = Timex.parse!(insight["createdAt"], "{ISO:Extended}")

      # Assert that now() and created_at do not differ by more than 2 seconds.
      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), created_at, 2, :seconds)
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
      Repo.insert!(%Project{name: "Santiment", ticker: "SAN", slug: "santiment"})
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
      ready_state = json_response(result, 200)["data"]["createInsight"]["readyState"]

      assert tag == %{"name" => "SAN"}
      assert related_projects == %{"ticker" => "SAN"}
      assert ready_state == Post.draft()
    end

    test "create an insight with image and retrieve the image hash and url", %{conn: conn} do
      image_url = upload_image(conn)

      mutation = """
      mutation {
        createInsight(title: "Awesome post", text: "Example body, urls: #{image_url}", imageUrls: ["#{image_url}"]) {
          images{
            imageUrl
          }
        }
      }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))

      [image] = json_response(result, 200)["data"]["createInsight"]["images"]

      assert image["imageUrl"] == image_url

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
      assert String.contains?(error["details"]["images"] |> hd(), "already used")
    end
  end

  describe "Update insight" do
    test "update post", %{conn: conn, user: user} do
      image_url = upload_image(conn)
      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          user: user,
          ready_state: Post.draft(),
          tags: [tag1],
          metrics: [
            build(:metric_postgres, name: "nvt"),
            build(:metric_postgres, name: "price_usd"),
            build(:metric_postgres, name: "daily_active_addresses")
          ]
        )

      mutation = """
        mutation {
          updateInsight(
            id: #{post.id}
            title: "Awesome post2"
            text: "Example body2"
            tags: ["#{tag2.name}"]
            imageUrls: ["#{image_url}"]
            metrics: ["nvt", "price_usd", "daily_active_addresses"]) {
              id
              title
              text
              metrics{ name }
              images{ imageUrl }
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

    test "cannot update not owned insight", %{conn: conn, staked_user: staked_user} do
      image_url = upload_image(conn)
      tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
      tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

      post =
        insert(:post,
          user: staked_user,
          ready_state: Post.draft(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(id: #{post.id} title: "Awesome post2", text: "Example body2", tags: ["#{tag2.name}"], imageUrls: ["#{image_url}"]) {
            id,
            title,
            text,
            images{
              imageUrl
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

    test "can update title and text of published insight", %{conn: conn, user: user} do
      upload_image(conn)

      post =
        insert(:post,
          user: user,
          ready_state: Post.published(),
          updated_at:
            Timex.shift(NaiveDateTime.utc_now(), seconds: -1) |> NaiveDateTime.truncate(:second)
        )

      mutation = """
        mutation {
          updateInsight(id: #{post.id}, title: "Awesome post2", text: "Example body2") {
            title
            text
            updatedAt
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      assert result["data"]["updateInsight"]["title"] == "Awesome post2"
      assert result["data"]["updateInsight"]["text"] == "Example body2"

      updated_at =
        Sanbase.DateTimeUtils.from_iso8601!(result["data"]["updateInsight"]["updatedAt"])
        |> DateTime.to_naive()

      assert NaiveDateTime.compare(updated_at, post.updated_at) == :gt
    end

    test "can update tags for published insight", %{conn: conn, user: user} do
      tag1 = insert(:tag, name: "PRJ1")
      tag2 = insert(:tag, name: "PRJ2")

      post =
        insert(:post,
          user: user,
          ready_state: Post.published(),
          tags: [tag1]
        )

      mutation = """
        mutation {
          updateInsight(id: #{post.id}, tags: ["#{tag2.name}"]) {
            tags {
              name
            }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      %{"data" => %{"updateInsight" => %{"tags" => tags}}} = result
      assert tags != [tag1]
      assert tags == [%{"name" => tag2.name}]
    end
  end

  describe "Delete insight" do
    test "deleting a post", %{user: user, conn: conn} do
      sanbase_post = insert(:post, user: user, state: Post.approved_state())

      Vote.create(%{post_id: sanbase_post.id, user_id: user.id})

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
        |> json_response(200)

      result_post = result["data"]["deleteInsight"]

      assert result_post["id"] == sanbase_post.id
    end

    test "deleting an insight which does not belong to the user - returns error", %{
      conn: conn,
      staked_user: staked_user
    } do
      sanbase_post = insert(:post, user: staked_user, state: Post.approved_state())

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

  describe "Publish insight" do
    test "successfully publishes in Discord and creates timeline event", %{
      user: user,
      conn: conn
    } do
      Sanbase.Mock.prepare_mock2(&Sanbase.Messaging.Insight.publish_in_discord/1, :ok)
      |> Sanbase.Mock.run_with_mocks(fn ->
        post =
          insert(:post,
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

        assert result["publishedAt"] != nil

        assert Sanbase.Timeline.TimelineEvent |> Repo.all() |> length() == 1
      end)
    end

    test "returns error when insight does not exist with the provided post_id", %{conn: conn} do
      result =
        %{id: 1000}
        |> publish_insight_mutation()
        |> execute_mutation_with_errors(conn)

      assert String.contains?(result["message"], "Cannot publish insight with id 1000")
    end

    test "still returns post when discord publish fails", %{user: user, conn: conn} do
      with_mocks([
        {Sanbase.Messaging.Insight, [],
         [publish_in_discord: fn _ -> {:error, "Error publishing in discord"} end]}
      ]) do
        post =
          insert(:post,
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
      staked_user: staked_user
    } do
      post =
        insert(:post,
          user: staked_user,
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
      user: user
    } do
      post =
        insert(:post,
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

  test "Get all tags", %{conn: conn} do
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

  test "Voting for an insight", %{conn: conn, user: user} do
    sanbase_post =
      %Post{
        user_id: user.id,
        title: "Awesome analysis",
        text: "Example MD text of the analysis",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    query = """
    mutation {
      vote(postId: #{sanbase_post.id}) {
        votes{
          totalVotes
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))
      |> json_response(200)

    result_post = result["data"]["vote"]

    assert result_post["votes"]["totalVotes"] == 1
  end

  test "Unvoting an insight", %{conn: conn, user: user} do
    sanbase_post =
      %Post{
        user_id: user.id,
        title: "Awesome analysis",
        text: "Some text here",
        state: Post.approved_state()
      }
      |> Repo.insert!()

    Vote.create(%{post_id: sanbase_post.id, user_id: user.id})

    query = """
    mutation {
      unvote(insightId: #{sanbase_post.id}) {
        votes { totalVotes }
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    result_post = json_response(result, 200)["data"]["unvote"]

    assert result_post["votes"]["totalVotes"] == 0
  end

  test "Voting is idempotent", context do
    %{conn: conn, user: user} = context
    post = insert(:post, %{user: user})

    assert match?(
             %{"data" => %{"vote" => %{"votedAt" => _}}},
             vote_for(conn, post.id)
           )

    assert match?(
             %{"data" => %{"vote" => %{"votedAt" => _}}},
             vote_for(conn, post.id)
           )

    assert match?(
             %{"data" => %{"vote" => %{"votedAt" => _}}},
             vote_for(conn, post.id)
           )
  end

  describe "Create chart event" do
    test "successfully creates chart event", context do
      conf = insert(:chart_configuration, is_public: true)

      args = %{
        title: "test chart event title",
        text: "test chart event text",
        chart_event_datetime: DateTime.utc_now() |> DateTime.to_iso8601(),
        chart_configuration_id: conf.id
      }

      query = create_chart_event(args)

      Sanbase.Mock.prepare_mock2(&Sanbase.Messaging.Insight.publish_in_discord/1, :ok)
      |> Sanbase.Mock.run_with_mocks(fn ->
        res = execute_mutation_with_success(query, "createChartEvent", context.conn)

        assert res["isChartEvent"]
        assert res["chartEventDatetime"] != nil
        assert res["chartConfigurationForEvent"]["id"] == conf.id

        {:ok, new_conf} =
          Sanbase.Chart.Configuration.by_id(conf.id, querying_user_id: context.user)

        assert length(new_conf.chart_events) == 1
      end)
    end

    test "chart configuration doesn't exist", context do
      query =
        create_chart_event(%{
          title: "test chart event title",
          text: "test chart event text",
          chart_event_datetime: DateTime.utc_now() |> DateTime.to_iso8601(),
          chart_configuration_id: 123
        })

      res = execute_mutation_with_errors(query, context.conn)
      assert res["message"] == "Chart configuration with id 123 does not exist or is private."
    end
  end

  test "Getting all insights filtered by from/to", %{
    user: user,
    conn: conn
  } do
    datetime_inside1 = Timex.now() |> Timex.shift(days: -10)
    datetime_inside2 = Timex.now() |> Timex.shift(days: -20)
    datetime_outside1 = Timex.now()
    datetime_outside2 = Timex.now() |> Timex.shift(days: -30)
    from = Timex.now() |> Timex.shift(days: -25) |> DateTime.to_iso8601()
    to = Timex.now() |> Timex.shift(days: -5) |> DateTime.to_iso8601()

    common_args = %{user: user, ready_state: Post.published(), state: Post.approved_state()}

    post1 = insert(:post, Map.put(common_args, :published_at, datetime_inside1))
    post2 = insert(:post, Map.put(common_args, :published_at, datetime_inside2))
    insert(:post, Map.put(common_args, :published_at, datetime_outside1))
    insert(:post, Map.put(common_args, :published_at, datetime_outside2))

    query = """
    {
      allInsights(from: "#{from}", to: "#{to}") {
        id
      }
    }
    """

    result = conn |> post("/graphql", query_skeleton(query, "allInsights"))

    assert json_response(result, 200)["data"]["allInsights"] ==
             [%{"id" => post1.id}, %{"id" => post2.id}]
  end

  # Helper functions

  defp create_chart_event(args) do
    """
    mutation {
      createChartEvent(
        title: "#{args.title}",
        text: "#{args.text}",
        chartConfigurationId: #{args.chart_configuration_id},
        chartEventDatetime: "#{args.chart_event_datetime}"
      ) {
        id
        isChartEvent
        chartEventDatetime
        chartConfigurationForEvent {
          id
        }
      }
    }
    """
  end

  defp publish_insight_mutation(post) do
    """
    mutation {
      publishInsight(id: #{post.id}) {
        id
        readyState
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

  defp vote_for(conn, id) do
    mutation = """
    mutation {
      vote(insightId: #{id}){
        votedAt
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
