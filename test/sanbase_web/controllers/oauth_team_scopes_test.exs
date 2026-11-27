defmodule SanbaseWeb.OAuthTeamScopesTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole

  @moduletag capture_log: true

  @redirect_uri "http://localhost:6274/oauth/callback"

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

  setup %{conn: conn} do
    role = insert(:role_mcp_knowledge_access)

    team_user = insert(:user, email: "support@santiment.net")
    {:ok, _} = UserRole.create(team_user.id, role.id)

    client_id =
      conn
      |> post("/oauth/register", %{
        "redirect_uris" => [@redirect_uri],
        "client_name" => "test",
        "grant_types" => ["authorization_code", "refresh_token"]
      })
      |> json_response(201)
      |> Map.fetch!("client_id")

    %{team_user: team_user, client_id: client_id}
  end

  defp authorize_query(client_id, scope, challenge) do
    URI.encode_query(%{
      "response_type" => "code",
      "client_id" => client_id,
      "redirect_uri" => @redirect_uri,
      "scope" => scope,
      "state" => "state",
      "code_challenge" => challenge,
      "code_challenge_method" => "S256"
    })
  end

  defp logged_in_conn(user) do
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    init_test_session(build_conn(), jwt_tokens)
  end

  # Approves the consent page and returns the query params of the redirect back
  # to the client, plus the PKCE verifier.
  defp approve(user, client_id, scope) do
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    location =
      user
      |> logged_in_conn()
      |> post("/oauth/authorize?" <> authorize_query(client_id, scope, challenge), %{
        "decision" => "approve"
      })
      |> redirected_to(302)

    assert String.starts_with?(location, @redirect_uri)
    {URI.decode_query(URI.parse(location).query), verifier}
  end

  defp get_token(user, client_id, scope) do
    {%{"code" => code}, verifier} = approve(user, client_id, scope)

    build_conn()
    |> post("/oauth/token", %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => @redirect_uri,
      "client_id" => client_id,
      "code_verifier" => verifier
    })
    |> json_response(200)
  end

  defp token_scopes(access_token) do
    Boruta.Ecto.Token
    |> Sanbase.Repo.get_by!(value: access_token)
    |> Map.fetch!(:scope)
    |> String.split()
  end

  defp knowledge_request(access_token), do: team_request("/mcp_knowledge", access_token)

  defp team_request(path, access_token) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("authorization", "Bearer " <> access_token)
    |> post(path, Jason.encode!(@initialize))
  end

  test "a user with the role gets a knowledge token that opens /mcp_knowledge",
       %{team_user: user, client_id: client_id} do
    %{"access_token" => access_token, "refresh_token" => refresh_token} =
      get_token(user, client_id, "mcp:knowledge")

    assert token_scopes(access_token) == ["mcp:knowledge"]
    assert knowledge_request(access_token).status == 200

    %{"access_token" => refreshed} =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_id" => client_id
      })
      |> json_response(200)

    assert knowledge_request(refreshed).status == 200
  end

  test "a token requested without the knowledge scope does not open /mcp_knowledge",
       %{team_user: user, client_id: client_id} do
    %{"access_token" => access_token} = get_token(user, client_id, "mcp")

    refute "mcp:knowledge" in token_scopes(access_token)
    assert knowledge_request(access_token).status == 401
  end

  test "a user without the role cannot get the knowledge scope", %{client_id: client_id} do
    user = insert(:user, email: "norole@santiment.net")

    assert {%{"error" => "invalid_scope"} = params, _verifier} =
             approve(user, client_id, "mcp:knowledge")

    refute Map.has_key?(params, "code")
  end

  test "the knowledge role does not grant the dev scope",
       %{team_user: user, client_id: client_id} do
    assert {%{"error" => "invalid_scope"}, _verifier} = approve(user, client_id, "mcp:dev")
  end

  test "a Dev MCP User gets an mcp:dev token that opens /mcp_dev but not /mcp_knowledge",
       %{client_id: client_id} do
    role = insert(:role_mcp_dev_access)
    user = insert(:user, email: "dev@santiment.net")
    {:ok, _} = UserRole.create(user.id, role.id)

    %{"access_token" => access_token} = get_token(user, client_id, "mcp:dev")

    assert team_request("/mcp_dev", access_token).status == 200
    assert knowledge_request(access_token).status == 401
  end

  test "the consent page warns when the knowledge scope is requested",
       %{team_user: user, client_id: client_id} do
    html =
      user
      |> logged_in_conn()
      |> get("/oauth/authorize?" <> authorize_query(client_id, "mcp:knowledge", "challenge"))
      |> html_response(200)

    assert html =~ "internal Santiment knowledge MCP"

    html =
      user
      |> logged_in_conn()
      |> get("/oauth/authorize?" <> authorize_query(client_id, "mcp", "challenge"))
      |> html_response(200)

    refute html =~ "internal Santiment knowledge MCP"
  end
end
