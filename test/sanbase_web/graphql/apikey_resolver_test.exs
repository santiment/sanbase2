defmodule SanbaseWeb.Graphql.ApikeyResolverTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Repo
  alias Sanbase.Auth.User

  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn}
  end

  test "generate a valid apikey", %{conn: conn} do
    result =
      generate_apikey(conn)
      |> json_response(200)

    %{
      "data" => %{
        "generateApikey" => %{
          "apikeys" => apikeys
        }
      }
    } = result

    # A single apikey should be generated
    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)

    # The generated apikey is valid
    {:ok, {token, _apikey}} = Sanbase.Auth.Hmac.split_apikey(apikey)
    assert Sanbase.Auth.Hmac.apikey_valid?(token, apikey)
  end

  test "revoke an apikey", %{conn: conn} do
    # Check that there is generated a single apikey
    result =
      generate_apikey(conn)
      |> json_response(200)

    %{
      "data" => %{
        "generateApikey" => %{
          "apikeys" => apikeys
        }
      }
    } = result

    assert Enum.count(apikeys) == 1
    apikey = List.first(apikeys)

    # Check that the apikey is now not present and not valid
    result2 =
      revoke_apikey(conn, apikey)
      |> json_response(200)

    %{
      "data" => %{
        "revokeApikey" => %{
          "apikeys" => apikeys2
        }
      }
    } = result2

    # There are no more apikeys
    assert apikeys2 == []

    # The previously valid apikey is now invalid
    {:ok, {token, _apikey}} = Sanbase.Auth.Hmac.split_apikey(apikey)
    assert Sanbase.Auth.Hmac.apikey_valid?(token, apikey)
  end

  # Private functions

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
