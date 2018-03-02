defmodule SanbaseWeb.Graphql.FileUploadTest do
  use SanbaseWeb.ConnCase, async: false

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

  @test_file_path "#{System.cwd()}/test/sanbase_web/graphql/assets/image.png"

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
      filename: "image.png",
      path: @test_file_path
    }

    result =
      conn
      |> post("/graphql", %{"query" => mutation, "img" => upload})

    [imageData] = json_response(result, 200)["data"]["uploadImage"]

    test_file_content = File.read!(@test_file_path)
    saved_file_content = File.read!(imageData["imageUrl"])

    assert imageData["contentHash"] ==
             "15e9f3c52e8c7f2444c5074f3db2049707d4c9ff927a00ddb8609bfae5925399"

    assert imageData["fileName"] != nil
    assert test_file_content == saved_file_content
  end
end
