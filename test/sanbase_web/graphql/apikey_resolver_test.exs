defmodule SanbaseWeb.Graphql.ApikeyResolverTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Repo

  alias Sanbase.Auth.{
    User,
    UserApikeyToken,
    Hmac
  }

  setup do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    user2 =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn2 = setup_jwt_auth(build_conn(), user2)

    %{conn: conn, conn2: conn2, user: user, user2: user2}
  end

  test "generate a valid apikey", %{conn: conn} do
    apikeys =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    # A single apikey should be generated
    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)

    # The generated apikey is valid
    assert apikey_valid?(apikey)
  end

  test "revoke an apikey", %{conn: conn} do
    # Check that there is generated a single apikey
    apikeys =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)

    # Check that the apikey is now not present and not valid
    apikeys2 =
      revoke_apikey(conn, apikey)
      |> json_response(200)
      |> extract_api_key_list()

    # There are no more apikeys
    assert apikeys2 == []

    # The previously valid apikey is now invalid
    refute apikey_valid?(apikey)
  end

  test "other users cannot revoke my apikey", %{conn: conn, conn2: conn2} do
    # Get apikey for user1
    apikey =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()
      |> List.first()

    # Check that user2 cannot revoke it
    result2 =
      revoke_apikey(conn2, apikey)
      |> json_response(200)

    err_struct = result2["errors"] |> List.first()
    assert err_struct["message"] =~ "Provided apikey is malformed or not valid"
  end

  test "can have more than one apikey", %{conn: conn} do
    generate_apikey(conn)
    generate_apikey(conn)

    [apikey1, apikey2, apikey3] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    assert apikey_valid?(apikey1)
    assert apikey_valid?(apikey2)
    assert apikey_valid?(apikey3)
  end

  test "revoke apikey twice", %{conn: conn} do
    [apikey] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    revoke_apikey(conn, apikey)
    revoke_apikey(conn, apikey)

    result =
      revoke_apikey(conn, apikey)
      |> json_response(200)

    err_struct = result["errors"] |> List.first()
    assert err_struct["message"] =~ "Provided apikey is malformed or not valid"
  end

  test "user dropped while the connection is up", %{conn: conn, user: user} do
    [apikey] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    Repo.delete(user)

    assert capture_log(fn ->
             revoke_apikey(conn, apikey)
           end) =~ "[warn] Invalid bearer token in request"
  end

  test "on delete user delete all user's tokens", %{conn: conn, user: user} do
    generate_apikey(conn)

    [apikey1, apikey2] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    Repo.delete(user)

    {:ok, {token1, _apikey}} = Hmac.split_apikey(apikey1)
    {:ok, {token2, _apikey}} = Hmac.split_apikey(apikey1)

    refute apikey_valid?(apikey1)
    refute apikey_valid?(apikey2)
    refute UserApikeyToken.has_token?(token1)
    refute UserApikeyToken.has_token?(token2)
  end

  # Private functions

  defp apikey_valid?(apikey) do
    {:ok, {token, _apikey}} = Hmac.split_apikey(apikey)
    Hmac.apikey_valid?(token, apikey)
  end

  defp generate_apikey(conn) do
    query = """
    mutation {
      generateApikey {
        apikeys
      }
    }
    """

    conn |> post("/graphql", mutation_skeleton(query))
  end

  defp extract_api_key_list(%{
         "data" => %{
           "generateApikey" => %{
             "apikeys" => apikeys
           }
         }
       }) do
    apikeys
  end

  defp extract_api_key_list(%{
         "data" => %{
           "revokeApikey" => %{
             "apikeys" => apikeys
           }
         }
       }) do
    apikeys
  end

  defp revoke_apikey(conn, apikey) do
    query = """
    mutation {
      revokeApikey(apikey: "#{apikey}") {
        apikeys
      }
    }
    """

    conn |> post("/graphql", mutation_skeleton(query))
  end
end
