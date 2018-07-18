defmodule SanbaseWeb.Graphql.PostTest do
  use SanbaseWeb.ConnCase, async: false
  use Mockery

  alias Sanbase.Voting.{Poll, Post, Vote, Tag}
  alias Sanbase.Auth.User
  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.InternalServices.Ethauth

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{
        salt: User.generate_salt(),
        san_balance:
          Decimal.mult(Decimal.new("10.000000000000000000"), Ethauth.san_token_decimals()),
        san_balance_updated_at: Timex.now(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    user2 =
      %User{
        salt: User.generate_salt(),
        san_balance:
          Decimal.mult(Decimal.new("10.000000000000000000"), Ethauth.san_token_decimals()),
        san_balance_updated_at: Timex.now(),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()

    {:ok, conn: conn, user: user, user2: user2}
  end

  test "getting a post by id", %{user: user, conn: conn} do
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
      post(id: #{post.id}) {
        text
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "post"))

    assert json_response(result, 200)["data"]["post"] |> Map.get("text") == post.text
  end

  test "getting a post by id for anon user", %{user: user} do
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
      post(id: #{post.id}) {
        id,
        title,
        shortDesc,
        state,
        createdAt,
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

    assert json_response(result, 200)["data"]["post"] |> Map.get("state") == post.state
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
        state: Post.approved_state(),
        ready_state: Post.published()
      }
      |> Repo.insert!()

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

  test "trying to get not allowed field from posts as anon user", %{user: user} do
    poll = Poll.find_or_insert_current_poll!()

    %Post{
      poll_id: poll.id,
      user_id: user.id,
      title: "Awesome analysis",
      short_desc: "Example analysis short description",
      text: "Example text, hoo",
      link: "http://www.google.com",
      state: Post.approved_state(),
      ready_state: Post.published()
    }
    |> Repo.insert!()

    query = """
    {
      allInsights {
        text,
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
        text,
        readyState
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsights"))

    assert json_response(result, 200)["data"]["allInsights"] |> List.first() |> Map.get("text") ==
             post.text
  end

  test "get only published or own posts", %{conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    other_user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    %Post{
      poll_id: poll.id,
      user_id: other_user.id,
      title: "Awesome analysis",
      short_desc: "Example analysis short description",
      text: "Example text, hoo",
      link: "http://www.google.com",
      state: Post.approved_state(),
      ready_state: Post.draft()
    }
    |> Repo.insert!()

    query = """
    {
      allInsights {
        id,
        text,
        readyState
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsights"))

    assert json_response(result, 200)["data"]["allInsights"] == []
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
        text
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
        text
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

  test "getting all posts ranked", %{user: user, user2: user2, conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        short_desc: "Example analysis short description",
        text: "Example text, hoo",
        link: "http://www.google.com",
        state: Post.approved_state(),
        ready_state: Post.published()
      }
      |> Repo.insert!()

    %Vote{}
    |> Vote.changeset(%{post_id: post.id, user_id: user.id})
    |> Repo.insert!()

    post2 =
      %Post{
        poll_id: poll.id,
        user_id: user2.id,
        title: "Awesome analysis2",
        short_desc: "Example analysis short description",
        text: "Example text, hoo2",
        link: "http://www.google.com",
        state: Post.approved_state(),
        ready_state: Post.published()
      }
      |> Repo.insert!()

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

    assert json_response(result, 200)["data"]["allInsights"] ==
             [%{"id" => "#{post2.id}"}, %{"id" => "#{post.id}"}]
  end

  test "Search posts by tag", %{user: user, conn: conn} do
    tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
    tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

    poll = Poll.find_or_insert_current_poll!()

    post = %Post{
      poll_id: poll.id,
      user_id: user.id,
      title: "Awesome analysis",
      short_desc: "Example analysis short description",
      text: "Example text, hoo",
      link: "http://www.google.com",
      state: Post.approved_state(),
      ready_state: Post.published()
    }

    post1 =
      Map.merge(post, %{tags: [tag1]})
      |> Repo.insert!()

    _post2 =
      Map.merge(post, %{tags: [tag2]})
      |> Repo.insert!()

    query = """
    {
      allInsightsByTag(tag: "#{tag1.name}"){
        id
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allInsightsByTag"))

    assert json_response(result, 200)["data"]["allInsightsByTag"] == [%{"id" => "#{post1.id}"}]
  end

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
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    sanbasePost = json_response(result, 200)["data"]["createPost"]

    assert sanbasePost["id"] != nil
    assert sanbasePost["title"] == "Awesome post"
    assert sanbasePost["state"] == nil
    assert sanbasePost["user"]["id"] == user.id |> Integer.to_string()
    assert sanbasePost["votes"]["totalSanVotes"] == 0

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

  test "deleting a post", %{user: user, conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        text: "Another example of MD text of the analysis",
        state: Post.approved_state()
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
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    poll = Poll.find_or_insert_current_poll!()

    sanbase_post =
      %Post{
        poll_id: poll.id,
        user_id: other_user.id,
        title: "Awesome analysis",
        text: "Text in body",
        state: Post.approved_state()
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

  test "update post", %{conn: conn, user: user} do
    image_url = upload_image(conn)
    poll = Poll.find_or_insert_current_poll!()
    tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
    tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome post",
        text: "Example body",
        ready_state: Post.draft(),
        tags: [tag1]
      }
      |> Repo.insert!()

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

  test "cannot update not owned post", %{conn: conn} do
    image_url = upload_image(conn)
    poll = Poll.find_or_insert_current_poll!()
    tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
    tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

    other_user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: other_user.id,
        title: "Awesome post",
        text: "Example body",
        ready_state: Post.draft(),
        tags: [tag1]
      }
      |> Repo.insert!()

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

  test "cannot update published posts", %{conn: conn, user: user} do
    image_url = upload_image(conn)
    poll = Poll.find_or_insert_current_poll!()
    tag1 = %Tag{name: "PRJ1"} |> Repo.insert!()
    tag2 = %Tag{name: "PRJ2"} |> Repo.insert!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome post",
        text: "Example body",
        ready_state: Post.published(),
        tags: [tag1]
      }
      |> Repo.insert!()

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

  @discourse_response_file "#{System.cwd()}/test/sanbase_web/graphql/assets/discourse_publish_response.json"
  test "publish post", %{user: user, conn: conn} do
    mock(
      HTTPoison,
      :post,
      {:ok,
       %HTTPoison.Response{
         body: File.read!(@discourse_response_file),
         status_code: 200
       }}
    )

    poll = Poll.find_or_insert_current_poll!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: user.id,
        title: "Awesome analysis",
        text: "Text in body",
        state: Post.approved_state(),
        ready_state: Post.draft()
      }
      |> Repo.insert!()

    query = """
    mutation {
      publishInsight(id: #{post.id}) {
        id,
        readyState,
        discourseTopicUrl
      }
    }
    """

    result =
      conn
      |> post("/graphql", mutation_skeleton(query))

    data = json_response(result, 200)["data"]
    assert data["publishInsight"]["readyState"] == Post.published()

    assert data["publishInsight"]["discourseTopicUrl"] ==
             "https://discourse.stage.internal.santiment.net/t/first-test-from-api2/234"
  end

  test "publish post returns error when user is not author", %{conn: conn} do
    poll = Poll.find_or_insert_current_poll!()

    other_user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    post =
      %Post{
        poll_id: poll.id,
        user_id: other_user.id,
        title: "Awesome analysis",
        text: "Text in body",
        state: Post.approved_state(),
        ready_state: Post.draft()
      }
      |> Repo.insert!()

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

  # Helper functions

  @test_file_path "#{System.cwd()}/test/sanbase_web/graphql/assets/image.png"
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
end
