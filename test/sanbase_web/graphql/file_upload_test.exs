defmodule SanbaseWeb.Graphql.FileUploadTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Auth.User
  alias Sanbase.Repo
  alias Sanbase.Voting.PostImage
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

    {:ok, conn: conn, user: user}
  end

  @test_file_path "#{System.cwd()}/test/sanbase_web/graphql/assets/image.png"
  @test_file_name "image.png"
  @test_file_hash "15e9f3c52e8c7f2444c5074f3db2049707d4c9ff927a00ddb8609bfae5925399"
  @test_file_hash_algorithm "sha256"
  @invalid_test_file_path "#{System.cwd()}/test/sanbase_web/graphql/assets/image_not_supported_extension.vxml"
  @invalid_test_file_name "image_not_supported_extension.vxml"

  test "upload an image", %{conn: conn} do
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
      filename: @test_file_name,
      path: @test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img" => upload})

    [imageData] = json_response(result, 200)["data"]["uploadImage"]

    test_file_content = File.read!(@test_file_path)
    saved_file_content = File.read!(imageData["imageUrl"])

    assert imageData["contentHash"] == @test_file_hash

    assert String.ends_with?(imageData["fileName"], @test_file_name)
    assert test_file_content == saved_file_content
  end

  test "upload of file with not supported extension fails", %{conn: conn} do
    mutation = """
      mutation {
        uploadImage(images: ["img"]){
          fileName
          contentHash,
          imageUrl,
          error
        }
      }
    """

    upload = %Plug.Upload{
      content_type: "application/octet-stream",
      filename: @invalid_test_file_name,
      path: @invalid_test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img" => upload})

    [imageData] = json_response(result, 200)["data"]["uploadImage"]

    assert imageData["error"] != nil
    assert String.ends_with?(imageData["fileName"], @invalid_test_file_name)
    assert imageData["imageUrl"] == nil
    assert imageData["contentHash"] == nil
  end

  test "upload of one valid and one invalid image", %{conn: conn} do
    mutation = """
      mutation {
        uploadImage(images: ["img1", "img2"]){
          fileName
          contentHash,
          imageUrl,
          error
        }
      }
    """

    upload1 = %Plug.Upload{
      content_type: "application/octet-stream",
      filename: @invalid_test_file_name,
      path: @invalid_test_file_path
    }

    upload2 = %Plug.Upload{
      content_type: "application/octet-stream",
      filename: @test_file_name,
      path: @test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img1" => upload1, "img2" => upload2})

    [image1, image2] = json_response(result, 200)["data"]["uploadImage"]

    assert image1["error"] != nil
    assert image2["error"] == nil

    assert String.ends_with?(image1["fileName"], @invalid_test_file_name)
    assert String.ends_with?(image2["fileName"], @test_file_name)

    assert image1["contentHash"] == nil
    assert image2["contentHash"] == @test_file_hash

    assert image1["imageUrl"] == nil
    assert image2["imageUrl"] != nil
  end

  test "upload metadata is correctly stored in postgres", %{conn: conn} do
    mutation = """
      mutation {
        uploadImage(images: ["img"]){
          fileName
          contentHash,
          imageUrl,
          error
        }
      }
    """

    upload = %Plug.Upload{
      content_type: "application/octet-stream",
      filename: @test_file_name,
      path: @test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img" => upload})

    [imageData] = json_response(result, 200)["data"]["uploadImage"]
    image_url = imageData["imageUrl"]

    image_meta_data = Repo.one(PostImage, image_url: image_url)

    assert image_meta_data.image_url == image_url
    assert String.ends_with?(image_meta_data.file_name, @test_file_name)
    assert image_meta_data.content_hash == @test_file_hash
    assert image_meta_data.hash_algorithm == @test_file_hash_algorithm
  end
end
