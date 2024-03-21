defmodule SanbaseWeb.Graphql.ApikeyResolverTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Repo
  alias Sanbase.Accounts.{UserApikeyToken, Hmac}

  @moduletag capture_log: true

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{user: user2} = insert(:subscription_custom, user: insert(:user))
    conn2 = setup_jwt_auth(build_conn(), user2)

    %{conn: conn, conn2: conn2, user: user, user2: user2}
  end

  test "can get apikey list with jwt auth", %{conn: conn} do
    _ = generate_apikey(conn)

    apikeys =
      get_apikeys(conn)
      |> json_response(200)
      |> get_in(["data", "currentUser", "apikeys"])

    assert is_list(apikeys)
    assert length(apikeys) > 0
  end

  test "cannot get apikey list with apikey auth", %{user: user} do
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey_conn = setup_apikey_auth(build_conn(), apikey)

    error =
      get_apikeys(apikey_conn)
      |> json_response(200)
      |> get_in(["errors"])
      |> hd()

    assert error["message"] =~ "Only JWT authenticated users can access their apikeys"
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
    # Generate and check that a valid single apikey is present
    apikeys =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)
    assert apikey_valid?(apikey)

    # Revoke and check that the apikey is now not present and not valid
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

    result = revoke_apikey(conn, apikey)
    {:ok, msg} = result.resp_body |> Jason.decode()

    assert result.status == 400
    assert msg["errors"]["details"] == "Invalid JSON Web Token (JWT)"
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

  test "cannot revoke malformed apikey", %{conn: conn} do
    [apikey] =
      generate_apikey(conn)
      |> json_response(200)
      |> extract_api_key_list()

    apikey = apikey <> "s"

    result =
      revoke_apikey(conn, apikey)
      |> json_response(200)

    err_struct = result["errors"] |> List.first()
    assert err_struct["message"] =~ "Provided apikey is malformed or not valid"
  end

  # Private functions

  defp apikey_valid?(apikey) do
    {:ok, {token, _apikey}} = Hmac.split_apikey(apikey)
    Hmac.apikey_valid?(token, apikey) && UserApikeyToken.has_token?(token)
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

  defp get_apikeys(conn) do
    query = """
    {
      currentUser{
        apikeys
      }
    }
    """

    conn |> post("/graphql", query_skeleton(query))
  end
end
