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

  defp oauth_token(user, scope) do
    {:ok, client} =
      %Boruta.Ecto.Client{}
      |> Boruta.Ecto.Client.create_changeset(%{redirect_uris: ["http://localhost/cb"]})
      |> Sanbase.Repo.insert()

    {:ok, token} =
      %Boruta.Ecto.Token{}
      |> Boruta.Ecto.Token.changeset(%{
        client_id: client.id,
        sub: to_string(user.id),
        scope: scope,
        access_token_ttl: client.access_token_ttl
      })
      |> Sanbase.Repo.insert()

    token.value
  end

  test "uses the same team rule as the knowledge MCP" do
    for email <- ["support@santiment.net", "someone@gmail.com", "x@evilsantiment.net", nil] do
      user = build(:user, email: email)

      assert Sanbase.MCP.Dev.Access.allowed?(user) ==
               Sanbase.MCP.Knowledge.Access.allowed?(user)
    end

    refute Sanbase.MCP.Dev.Access.allowed?(
             build(:user, email: "dev@santiment.net", is_mcp_banned: true)
           )
  end

  describe "/mcp_dev gate" do
    test "rejects requests without credentials with 401 and OAuth discovery", %{conn: conn} do
      for body <- [@initialize, @tools_list] do
        conn = mcp_request(conn, body)

        assert conn.status == 401
        assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
        assert www_authenticate =~ "/.well-known/oauth-protected-resource/mcp_dev"
        assert www_authenticate =~ ~s(scope="mcp:dev")
      end
    end

    test "rejects invalid credentials with 401", %{conn: conn} do
      conn = mcp_request(conn, @initialize, "Apikey not-a-real-key")
      assert conn.status == 401
    end

    test "rejects OAuth tokens issued for /mcp without mcp:dev scope", %{conn: conn} do
      user = insert(:user, email: "dev@santiment.net")
      public_mcp_token = oauth_token(user, "mcp")

      conn = mcp_request(conn, @initialize, "Bearer #{public_mcp_token}")
      assert conn.status == 401
      assert [www_authenticate] = get_resp_header(conn, "www-authenticate")
      assert www_authenticate =~ ~s(scope="mcp:dev")
    end

    test "accepts OAuth tokens with mcp:dev scope for team members", %{conn: conn} do
      user = insert(:user, email: "dev@santiment.net")
      dev_token = oauth_token(user, "mcp:dev")

      conn = mcp_request(conn, @initialize, "Bearer #{dev_token}")
      assert conn.status == 200
    end

    test "rejects MCP-banned team members with 403", %{conn: conn} do
      user = insert(:user, email: "banned@santiment.net", is_mcp_banned: true)
      {:ok, key} = Sanbase.Accounts.Apikey.generate_apikey(user)

      conn = mcp_request(conn, @initialize, "Apikey #{key}")
      assert conn.status == 403
      assert get_resp_header(conn, "www-authenticate") == []

      assert %{"error" => "forbidden", "error_description" => desc} =
               Jason.decode!(conn.resp_body)

      assert desc =~ "banned"
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

  test "Dev.Server rejects a user banned mid-session even when cached in frame assigns" do
    user = insert(:user, email: "dev@santiment.net")
    frame = Anubis.Server.Frame.new(%{current_user: user})

    Sanbase.Accounts.User.mcp_ban!(user, "compromised")

    assert {:error, %Anubis.MCP.Error{}, _frame} =
             Sanbase.MCP.Dev.Server.handle_request(@tools_list, frame)
  end

  test "ResourceOwners grants team MCP scopes only to @santiment.net users" do
    team_scopes =
      Sanbase.OAuth.ResourceOwners.authorized_scopes(%Boruta.Oauth.ResourceOwner{
        sub: "1",
        username: "dev@santiment.net"
      })
      |> Enum.map(& &1.name)

    outsider_scopes =
      Sanbase.OAuth.ResourceOwners.authorized_scopes(%Boruta.Oauth.ResourceOwner{
        sub: "2",
        username: "someone@gmail.com"
      })
      |> Enum.map(& &1.name)

    assert "mcp:dev" in team_scopes
    assert "mcp:knowledge" in team_scopes
    refute "mcp:dev" in outsider_scopes
    refute "mcp:knowledge" in outsider_scopes
  end

  test "records ToolInvocation and enforces rate limit on dev tools/call" do
    user = insert(:user, email: "dev@santiment.net")
    frame = Anubis.Server.Frame.new(%{current_user: user})

    Application.put_env(:sanbase, :mcp_dev_rate_limit_per_minute, 1)
    on_exit(fn -> Application.delete_env(:sanbase, :mcp_dev_rate_limit_per_minute) end)

    call_request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{"name" => "describe_tables", "arguments" => %{"tables" => [" "]}}
    }

    assert {:reply, %{"isError" => true}, _frame} =
             Sanbase.MCP.Dev.Server.handle_request(call_request, frame)

    # Second call within the same minute is rate-limited
    assert {:reply, %{"isError" => true, "content" => [%{"text" => text}]}, _frame} =
             Sanbase.MCP.Dev.Server.handle_request(call_request, frame)

    assert text =~ "[transient]"
    assert text =~ "rate limit"

    invocations =
      Sanbase.MCP.ToolInvocation.list_invocations([])
      |> Enum.filter(&(&1.user_id == user.id and &1.tool_name == "describe_tables"))

    assert length(invocations) == 2
    assert Enum.all?(invocations, &(&1.server == "mcp_dev"))
    assert [_, _] = Sanbase.MCP.ToolInvocation.list_invocations(server: "mcp_dev")
    assert [] = Sanbase.MCP.ToolInvocation.list_invocations(server: "mcp")
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
    assert www_authenticate =~ ~s(scope="mcp:knowledge")
  end

  test "serves path-suffixed protected resource metadata", %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-protected-resource/mcp_dev")

    assert %{
             "resource" => resource,
             "authorization_servers" => [_],
             "scopes_supported" => ["mcp:dev"]
           } = json_response(conn, 200)

    assert String.ends_with?(resource, "/mcp_dev")
  end

  test "the authorization server metadata does not advertise the team scopes", %{conn: conn} do
    %{"scopes_supported" => scopes} =
      conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

    assert "mcp" in scopes
    refute "mcp:dev" in scopes
    refute "mcp:knowledge" in scopes
  end
end
