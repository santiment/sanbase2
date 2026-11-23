defmodule Sanbase.MCP.Dev.AuthTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

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

    post(conn, "/mcp_dev", Jason.encode!(body))
  end

  defp apikey(email) do
    user = insert(:user, email: email)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
    apikey
  end

  test "uses the same team rule as the knowledge MCP" do
    for email <- ["support@santiment.net", "someone@gmail.com", "x@evilsantiment.net", nil] do
      user = build(:user, email: email)

      assert Sanbase.MCP.Dev.Access.allowed?(user) ==
               Sanbase.MCP.Knowledge.Access.allowed?(user)
    end
  end

  describe "/mcp_dev gate" do
    test "rejects requests without credentials with 401 and OAuth discovery", %{conn: conn} do
      for body <- [@initialize, @tools_list] do
        conn = mcp_request(conn, body)

        assert conn.status == 401
        assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
        assert www_authenticate =~ "/.well-known/oauth-protected-resource/mcp_dev"
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

      assert %{"error" => "forbidden", "error_description" => description} =
               Jason.decode!(conn.resp_body)

      assert description =~ "dev MCP"
    end

    test "lets @santiment.net users through to the dev MCP server", %{conn: conn} do
      conn = mcp_request(conn, @initialize, "Apikey #{apikey("dev@santiment.net")}")

      assert conn.status == 200

      assert %{"result" => %{"serverInfo" => %{"name" => "santiment-dev"}}} =
               Jason.decode!(conn.resp_body)
    end
  end

  test "lists the dev tools to team members", %{conn: conn} do
    conn = mcp_request(conn, @tools_list, "Apikey #{apikey("dev@santiment.net")}")

    assert %{"result" => %{"tools" => tools}} = Jason.decode!(conn.resp_body)

    assert tools |> Enum.map(& &1["name"]) |> Enum.sort() ==
             ~w(describe_tables execute_sql list_tables social_messages tweets_by_author)

    execute_sql = Enum.find(tools, &(&1["name"] == "execute_sql"))
    assert execute_sql["inputSchema"]["required"] == ["sql"]
    assert execute_sql["inputSchema"]["properties"]["parameters"]["type"] == "object"
  end

  test "the knowledge MCP gate still points OAuth at its own resource", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/mcp_knowledge", Jason.encode!(@initialize))

    assert conn.status == 401
    assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
    assert www_authenticate =~ "/.well-known/oauth-protected-resource/mcp_knowledge\""
  end

  test "serves path-suffixed protected resource metadata", %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-protected-resource/mcp_dev")

    assert %{"resource" => resource, "authorization_servers" => [_]} = json_response(conn, 200)
    assert String.ends_with?(resource, "/mcp_dev")
  end
end
