defmodule SanbaseWeb.Graphql.InsightImageTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Insight.Post
  alias Sanbase.Insight.PostImage

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  @test_file_path "#{File.cwd!()}/test/sanbase_web/graphql/assets/image.png"

  describe "images field via GraphQL" do
    test "returns DB-linked images", %{conn: conn} do
      image_url = upload_image(conn)

      mutation = """
        mutation {
          createInsight(title: "Test post", text: "some text", imageUrls: ["#{image_url}"]) {
            id
            images { imageUrl }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      images = result["data"]["createInsight"]["images"]
      assert length(images) == 1
      assert hd(images)["imageUrl"] == image_url
    end

    test "returns regex-extracted images from text for old insights", %{user: user} do
      # Simulate an old insight with image URL in text but no DB PostImage link
      image_url = "/tmp/sanbase/filestore-test/old_image.png"

      post =
        insert(:post,
          user: user,
          text: "Here is an image #{image_url} in the text",
          state: Post.approved_state(),
          ready_state: Post.published()
        )

      conn = setup_jwt_auth(build_conn(), user)

      query = """
      {
        insight(id: #{post.id}) {
          images { imageUrl }
        }
      }
      """

      result =
        conn
        |> post("/graphql", query_skeleton(query, "insight"))
        |> json_response(200)

      images = result["data"]["insight"]["images"]
      assert length(images) == 1
      assert hd(images)["imageUrl"] == image_url
    end

    test "deduplicates images found in both DB and text", %{conn: conn} do
      image_url = upload_image(conn)

      # Create insight with image in both imageUrls and embedded in text
      mutation = """
        mutation {
          createInsight(title: "Dedup test", text: "Look at #{image_url}", imageUrls: ["#{image_url}"]) {
            id
            images { imageUrl }
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      images = result["data"]["createInsight"]["images"]
      # Should only appear once despite being in both DB and text
      assert length(images) == 1
      assert hd(images)["imageUrl"] == image_url
    end
  end

  describe "auto-link on create" do
    test "auto-links uploaded image when its URL appears in text", %{conn: conn, user: user} do
      image_url = upload_image(conn)

      # Create insight with the image URL in the text but NOT in imageUrls
      mutation = """
        mutation {
          createInsight(title: "Auto-link test", text: "Check #{image_url}") {
            id
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(mutation))
        |> json_response(200)

      post_id = result["data"]["createInsight"]["id"]

      # Verify the PostImage is now linked to the post
      image = Sanbase.Repo.get_by(PostImage, image_url: image_url)
      assert image.post_id == post_id
      assert image.user_id == user.id
    end
  end

  describe "auto-link on update" do
    test "auto-links images when text is updated with image URL", %{conn: conn} do
      image_url = upload_image(conn)

      # Create insight without the image
      create_mutation = """
        mutation {
          createInsight(title: "Update link test", text: "no image here") {
            id
          }
        }
      """

      result =
        conn
        |> post("/graphql", mutation_skeleton(create_mutation))
        |> json_response(200)

      post_id = result["data"]["createInsight"]["id"]

      # Update the insight to include the image URL in text
      update_mutation = """
        mutation {
          updateInsight(id: #{post_id}, text: "now has #{image_url}") {
            id
          }
        }
      """

      conn
      |> post("/graphql", mutation_skeleton(update_mutation))
      |> json_response(200)

      # Verify the PostImage is now linked to the post
      image = Sanbase.Repo.get_by(PostImage, image_url: image_url)
      assert image.post_id == post_id
    end
  end

  # Helper

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
      filename: "#{System.unique_integer([:positive])}_image.png",
      path: @test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img" => upload})

    [image_data] = json_response(result, 200)["data"]["uploadImage"]
    image_data["imageUrl"]
  end
end
