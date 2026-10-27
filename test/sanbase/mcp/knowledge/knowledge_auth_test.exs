defmodule Sanbase.MCP.Knowledge.AuthTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.MCP.Knowledge.Access

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

  defp mcp_request(conn, body, authorization \\ nil) do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn =
      if authorization, do: put_req_header(conn, "authorization", authorization), else: conn

    post(conn, "/mcp_knowledge", Jason.encode!(body))
  end

  defp apikey(email) do
    user = insert(:user, email: email)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey
  end

  describe "Access.allowed?/1" do
    test "allows only @santiment.net emails" do
      assert Access.allowed?(build(:user, email: "support@santiment.net"))
      assert Access.allowed?(build(:user, email: " Support@Santiment.NET "))

      refute Access.allowed?(build(:user, email: "someone@gmail.com"))
      refute Access.allowed?(build(:user, email: "x@evilsantiment.net"))
      refute Access.allowed?(build(:user, email: "x@santiment.net.evil.com"))
      refute Access.allowed?(build(:user, email: nil))
      refute Access.allowed?(nil)
    end
  end

  describe "/mcp_knowledge gate" do
    test "rejects requests without credentials with 401 and OAuth discovery", %{conn: conn} do
      for body <- [@initialize, @tools_list] do
        conn = mcp_request(conn, body)

        assert conn.status == 401

        assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
        assert www_authenticate =~ "/.well-known/oauth-protected-resource/mcp_knowledge"
      end
    end

    test "rejects invalid credentials with 401", %{conn: conn} do
      conn = mcp_request(conn, @initialize, "Apikey not-a-real-key")
      assert conn.status == 401
    end

    test "rejects non-team users with 403 and no OAuth retry", %{conn: conn} do
      conn = mcp_request(conn, @initialize, "Apikey #{apikey("someone@gmail.com")}")

      assert conn.status == 403
      assert get_resp_header(conn, "www-authenticate") == []
      assert %{"error" => "forbidden"} = Jason.decode!(conn.resp_body)
    end

    test "lets @santiment.net users through to the MCP server", %{conn: conn} do
      conn = mcp_request(conn, @initialize, "Apikey #{apikey("support@santiment.net")}")

      assert conn.status == 200

      assert %{"result" => %{"serverInfo" => %{"name" => "santiment-knowledge"}}} =
               Jason.decode!(conn.resp_body)
    end
  end

  test "serves path-suffixed protected resource metadata", %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-protected-resource/mcp_knowledge")

    assert %{"resource" => resource, "authorization_servers" => [_]} = json_response(conn, 200)
    assert String.ends_with?(resource, "/mcp_knowledge")
  end
end
