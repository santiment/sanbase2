defmodule Sanbase.MCP.AuthTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.MCP.Auth

  setup do
    user = insert(:user)

    {:ok, oauth_client} =
      %Boruta.Ecto.Client{}
      |> Boruta.Ecto.Client.create_changeset(%{
        redirect_uris: ["http://localhost:4000/callback"]
      })
      |> Sanbase.Repo.insert()

    {:ok, token} =
      %Boruta.Ecto.Token{}
      |> Boruta.Ecto.Token.changeset(%{
        client_id: oauth_client.id,
        sub: to_string(user.id),
        scope: "",
        access_token_ttl: oauth_client.access_token_ttl
      })
      |> Sanbase.Repo.insert()

    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

    %{user: user, bearer_token: token.value, apikey: apikey}
  end

  describe "headers_list_to_user/1" do
    test "resolves user from OAuth bearer token", context do
      headers = [{"authorization", "Bearer #{context.bearer_token}"}]
      user = Auth.headers_list_to_user(headers)

      assert user.id == context.user.id
    end

    test "resolves user from Apikey scheme", context do
      headers = [{"authorization", "Apikey #{context.apikey}"}]
      user = Auth.headers_list_to_user(headers)

      assert user.id == context.user.id
    end

    test "resolves user from Bearer Apikey scheme", context do
      headers = [{"authorization", "Bearer Apikey #{context.apikey}"}]
      user = Auth.headers_list_to_user(headers)

      assert user.id == context.user.id
    end

    test "returns nil when no authorization header" do
      assert Auth.headers_list_to_user([]) == nil
    end

    test "returns nil for invalid OAuth token" do
      headers = [{"authorization", "Bearer invalid_token"}]
      assert Auth.headers_list_to_user(headers) == nil
    end

    test "returns nil for invalid apikey" do
      headers = [{"authorization", "Apikey invalid_apikey"}]
      assert Auth.headers_list_to_user(headers) == nil
    end
  end

  describe "get_apikey/1" do
    test "extracts apikey from Apikey scheme", context do
      headers = [{"authorization", "Apikey #{context.apikey}"}]
      assert Auth.get_apikey(headers) == context.apikey
    end

    test "extracts apikey from Bearer Apikey scheme", context do
      headers = [{"authorization", "Bearer Apikey #{context.apikey}"}]
      assert Auth.get_apikey(headers) == context.apikey
    end

    test "extracts value from Bearer scheme when it is an apikey", context do
      headers = [{"authorization", "Bearer #{context.apikey}"}]
      assert Auth.get_apikey(headers) == context.apikey
    end

    test "returns nil for OAuth bearer token", context do
      headers = [{"authorization", "Bearer #{context.bearer_token}"}]
      assert Auth.get_apikey(headers) == nil
    end

    test "returns nil when no authorization header" do
      assert Auth.get_apikey([]) == nil
    end
  end

  describe "get_auth_method/1" do
    test "returns oauth for OAuth bearer token", context do
      headers = [{"authorization", "Bearer #{context.bearer_token}"}]
      assert Auth.get_auth_method(headers) == "oauth"
    end

    test "returns apikey for Apikey scheme", context do
      headers = [{"authorization", "Apikey #{context.apikey}"}]
      assert Auth.get_auth_method(headers) == "apikey"
    end

    test "returns apikey for Bearer Apikey scheme", context do
      headers = [{"authorization", "Bearer Apikey #{context.apikey}"}]
      assert Auth.get_auth_method(headers) == "apikey"
    end

    test "returns apikey for Bearer scheme when it is an apikey", context do
      headers = [{"authorization", "Bearer #{context.apikey}"}]
      assert Auth.get_auth_method(headers) == "apikey"
    end

    test "returns nil when no authorization header" do
      assert Auth.get_auth_method([]) == nil
    end
  end

  describe "has_authorization_header?/1" do
    test "returns true when authorization header present" do
      headers = [{"authorization", "Bearer token"}]
      assert Auth.has_authorization_header?(headers) == true
    end

    test "returns false when no authorization header" do
      assert Auth.has_authorization_header?([]) == false
    end
  end
end
