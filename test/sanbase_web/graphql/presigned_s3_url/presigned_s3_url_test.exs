defmodule SanbaseWeb.Graphql.PresignedS3UrlTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.PresignedS3Url

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    %{user: user, conn: conn}
  end

  @url "https://s3.eu-central-1.amazonaws.com/api-users-datasets/dataset?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=test_id%2F20221121%2Feu-central-1%2Fs3%2Faws4_request&X-Amz-Date=20221121T100458Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=signature"
  test "get a presigned S3 url", context do
    Sanbase.Mock.prepare_mock2(&PresignedS3Url.S3.generate_presigned_url/3, {:ok, @url})
    |> Sanbase.Mock.run_with_mocks(fn ->
      url =
        get_presigned_s3_url(context.conn, "dataset")
        |> get_in(["data", "getPresignedS3Url"])

      assert url =~ "https://s3.eu-central-1.amazonaws.com/api-users-datasets/dataset"
    end)
  end

  test "presigned url S3 expires", context do
    now = DateTime.utc_now()
    dt = DateTime.utc_now() |> DateTime.add(PresignedS3Url.expires_in() + 10, :second)

    dt_mock =
      [
        fn -> now end,
        fn -> dt end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 0)

    Sanbase.Mock.prepare_mock(Sanbase.PresignedS3Url.S3, :utc_now, dt_mock)
    |> Sanbase.Mock.prepare_mock2(&PresignedS3Url.S3.generate_presigned_url/3, {:ok, @url})
    |> Sanbase.Mock.run_with_mocks(fn ->
      # # dt is mocked as now
      _url = get_presigned_s3_url(context.conn, "dataset")

      # # dt is mocked as now + expires_in + 10 seconds
      error_msg =
        get_presigned_s3_url(context.conn, "dataset")
        |> get_in(["errors", Access.at(0), "message"])

      assert_called(Sanbase.PresignedS3Url.S3.utc_now())
      assert error_msg =~ "A presigned S3 URL has been generated and has already expired at"
    end)
  end

  defp get_presigned_s3_url(conn, object) do
    query = """
    {
      getPresignedS3Url(object: "#{object}")
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
