defmodule SanbaseWeb.Graphql.ApikeyResolverTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Repo

  alias Sanbase.Auth.{
    UserApikeyToken,
    Hmac
  }

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{user: user2} = insert(:subscription_premium, user: insert(:user))
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
    assert msg["errors"]["details"] == "Bad authorization header: Invalid JSON Web Token (JWT)"
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

  test "access realtime data behind API delay san staking", %{conn2: conn2} do
    # Store some data recent data
    slug = "santiment"
    datetime1 = Timex.shift(Timex.now(), hours: -1)
    datetime2 = Timex.now()
    init_databases(slug, datetime1, datetime2)

    # Get an apikey and build API conn
    [apikey] =
      generate_apikey(conn2)
      |> json_response(200)
      |> extract_api_key_list()

    conn_apikey = setup_apikey_auth(build_conn(), apikey)

    query = token_age_consumed_query(slug, datetime1, datetime2)

    result =
      conn_apikey
      |> post("/graphql", query_skeleton(query, "tokenAgeConsumed"))
      |> json_response(200)

    %{
      "data" => %{
        "tokenAgeConsumed" => token_age_consumed
      }
    } = result

    assert length(token_age_consumed) > 0
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

  defp init_databases(slug, datetime1, datetime2) do
    require Sanbase.TimescaleFactory

    contract_address = "0" <> Sanbase.TestUtils.random_string()

    Sanbase.TimescaleFactory.insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime1,
      token_age_consumed: 5000
    })

    Sanbase.TimescaleFactory.insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime2,
      token_age_consumed: 1000
    })

    insert(:project, %{
      name: "Santiment",
      ticker: "SAN",
      slug: slug,
      main_contract_address: contract_address
    })
  end

  defp token_age_consumed_query(slug, datetime1, datetime2) do
    """
    {
      tokenAgeConsumed(
        slug: "#{slug}",
        from: "#{datetime1}",
        to: "#{datetime2}",
        interval: "30m") {
          tokenAgeConsumed
          datetime
      }
    }
    """
  end
end
