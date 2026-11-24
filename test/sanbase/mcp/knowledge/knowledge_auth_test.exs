defmodule Sanbase.MCP.Knowledge.AuthTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole
  alias Sanbase.MCP.Knowledge.Access
  alias Sanbase.TestHelpers

  @moduletag capture_log: true

  @initialize %{
    "jsonrpc" => "2.0",
    "id" => 1,
    "method" => "initialize",
    "params" => %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "test", "version" => "1.0.0"}
    }
  }

  @tools_list %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}

  setup do
    role = insert(:role_mcp_knowledge_access)
    %{role: role}
  end

  defp mcp_request(conn, body, authorization \\ nil) do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn =
      if authorization, do: put_req_header(conn, "authorization", authorization), else: conn

    post(conn, "/mcp_knowledge", Jason.encode!(body))
  end

  defp team_user(role, email \\ "support@santiment.net") do
    user = insert(:user, email: email)
    {:ok, _} = UserRole.create(user.id, role.id)
    user
  end

  defp bearer(user, scope), do: "Bearer " <> TestHelpers.setup_mcp_oauth_client(user, scope)

  defp assert_oauth_challenge(conn) do
    assert conn.status == 401
    assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
    assert www_authenticate =~ "/.well-known/oauth-protected-resource/mcp_knowledge"
    assert www_authenticate =~ ~s(scope="mcp:knowledge")
  end

  describe "Access.allowed?/1" do
    test "requires a @santiment.net email and the knowledge role", %{role: role} do
      assert Access.allowed?(team_user(role))
      assert Access.allowed?(team_user(role, " Ops@Santiment.NET "))

      refute Access.allowed?(insert(:user, email: "norole@santiment.net"))
      refute Access.allowed?(team_user(role, "someone@gmail.com"))
      refute Access.allowed?(team_user(role, "x@evilsantiment.net"))
      refute Access.allowed?(team_user(role, "x@santiment.net.evil.com"))
      refute Access.allowed?(build(:user, email: nil))

      banned = team_user(role, "banned@santiment.net")
      refute Access.allowed?(%{banned | is_mcp_banned: true})
      refute Access.allowed?(nil)
    end
  end

  describe "/mcp_knowledge gate" do
    test "rejects requests without credentials with 401 and an OAuth challenge", %{conn: conn} do
      for body <- [@initialize, @tools_list] do
        conn |> mcp_request(body) |> assert_oauth_challenge()
      end
    end

    test "rejects invalid credentials with 401", %{conn: conn} do
      conn |> mcp_request(@initialize, "Bearer not-a-real-token") |> assert_oauth_challenge()
    end

    test "rejects the API key of a user with the role", %{conn: conn, role: role} do
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(team_user(role))

      for authorization <- ["Apikey #{apikey}", "Bearer Apikey #{apikey}", "Bearer #{apikey}"] do
        conn |> mcp_request(@initialize, authorization) |> assert_oauth_challenge()
      end
    end

    test "rejects a token without mcp:knowledge, such as one issued for /mcp or /mcp_dev",
         %{conn: conn, role: role} do
      user = team_user(role)

      for scope <- ["", "mcp", "mcp:dev", "openid profile email offline_access read write mcp"] do
        conn = mcp_request(conn, @initialize, bearer(user, scope))

        assert_oauth_challenge(conn)
      end
    end

    test "rejects a knowledge token of a user without the role with 403", %{conn: conn} do
      user = insert(:user, email: "norole@santiment.net")
      conn = mcp_request(conn, @initialize, bearer(user, "mcp:knowledge"))

      assert conn.status == 403
      assert get_resp_header(conn, "www-authenticate") == []
      assert %{"error" => "forbidden"} = Jason.decode!(conn.resp_body)
    end

    test "rejects a knowledge token after the role is revoked", %{conn: conn, role: role} do
      user = team_user(role)
      authorization = bearer(user, "mcp:knowledge")
      UserRole.delete(user.id, role.id)

      assert mcp_request(conn, @initialize, authorization).status == 403
    end

    test "lets a knowledge token of a user with the role through", %{conn: conn, role: role} do
      conn = mcp_request(conn, @initialize, bearer(team_user(role), "mcp mcp:knowledge"))

      assert conn.status == 200

      assert %{"result" => %{"serverInfo" => %{"name" => "santiment-knowledge"}}} =
               Jason.decode!(conn.resp_body)
    end
  end

  test "serves path-suffixed protected resource metadata with the knowledge scope",
       %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-protected-resource/mcp_knowledge")

    assert %{
             "resource" => resource,
             "authorization_servers" => [_],
             "scopes_supported" => ["mcp:knowledge"]
           } = json_response(conn, 200)

    assert String.ends_with?(resource, "/mcp_knowledge")
  end

  test "does not advertise the knowledge scope for /mcp", %{conn: conn} do
    refute conn
           |> get("/.well-known/oauth-protected-resource")
           |> json_response(200)
           |> Map.has_key?("scopes_supported")

    %{"scopes_supported" => scopes} =
      conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

    refute "mcp:knowledge" in scopes
  end
end
