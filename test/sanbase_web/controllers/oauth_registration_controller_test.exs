defmodule SanbaseWeb.OAuthRegistrationControllerTest do
  use SanbaseWeb.ConnCase, async: false

  @redirect_uri "http://localhost:6274/oauth/callback"

  test "dynamic registration keeps the server-side client settings", %{conn: conn} do
    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/oauth/register", %{
        "client_name" => "MCP test client",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "token_endpoint_auth_method" => "none"
      })
      |> json_response(201)

    assert response["client_name"] == "MCP test client"
    assert response["redirect_uris"] == [@redirect_uri]
    assert response["grant_types"] == ["authorization_code", "refresh_token"]
    assert is_binary(response["client_secret"])

    client = Sanbase.Repo.get!(Boruta.Ecto.Client, response["client_id"])

    assert client.pkce == true
    assert client.public_refresh_token == true
    assert client.confidential == false
    assert client.access_token_ttl == 86_400
    assert client.authorization_code_ttl == 60
    assert client.refresh_token_ttl == 30 * 86_400
    assert client.supported_grant_types == ["authorization_code", "refresh_token"]
  end

  test "dynamic registration drops grant types that are not offered", %{conn: conn} do
    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/oauth/register", %{
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["client_credentials", "password", "refresh_token"]
      })
      |> json_response(201)

    assert response["grant_types"] == ["authorization_code", "refresh_token"]

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/oauth/register", %{
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["client_credentials"]
      })
      |> json_response(201)

    assert response["grant_types"] == ["authorization_code"]
  end

  test "dynamic registration rejects an unsupported token endpoint auth method", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/oauth/register", %{
        "redirect_uris" => [@redirect_uri],
        "token_endpoint_auth_method" => "not_a_method"
      })

    assert conn.status in 400..499
  end
end
