defmodule Sanbase.MCP.AuthPlugTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  setup do
    {:ok, oauth_client} =
      %Boruta.Ecto.Client{}
      |> Boruta.Ecto.Client.create_changeset(%{
        redirect_uris: ["http://localhost:4000/callback"]
      })
      |> Sanbase.Repo.insert()

    %{oauth_client: oauth_client}
  end

  test "authenticates an OAuth token with a user id sub", %{oauth_client: client} do
    user = insert(:user)
    token = insert_token(client, to_string(user.id))

    conn = call_plug(token.value)

    refute conn.halted
    assert conn.assigns.current_user.id == user.id
  end

  test "rejects an OAuth token without a sub", %{oauth_client: client} do
    token = insert_token(client, nil)

    conn = call_plug(token.value)

    assert conn.halted
    assert conn.status == 401
  end

  defp insert_token(client, sub) do
    {:ok, token} =
      %Boruta.Ecto.Token{}
      |> Boruta.Ecto.Token.changeset(%{
        client_id: client.id,
        sub: sub,
        scope: "",
        access_token_ttl: client.access_token_ttl
      })
      |> Sanbase.Repo.insert()

    token
  end

  defp call_plug(token_value) do
    build_conn(:post, "/mcp", %{"method" => "tools/call"})
    |> put_req_header("authorization", "Bearer #{token_value}")
    |> Sanbase.MCP.AuthPlug.call([])
  end
end
