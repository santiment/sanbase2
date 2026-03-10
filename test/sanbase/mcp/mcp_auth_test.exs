defmodule SanbaseWeb.Graphql.MCPAuthTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  setup do
    user = insert(:user)

    # Create an OAuth client and access token for Bearer authentication
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

    on_exit(fn ->
      if pid = Process.whereis(Sanbase.MCP.Client) do
        try do
          GenServer.stop(pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{user: user, bearer_token: token.value}
  end

  defp wait_for_initialization(attempts \\ 10) do
    if Sanbase.MCP.Client.get_server_capabilities() do
      :ok
    else
      if attempts > 0 do
        Process.sleep(100)
        wait_for_initialization(attempts - 1)
      else
        flunk("MCP client did not initialize in time")
      end
    end
  end

  test "authentication", context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Bearer #{context.bearer_token}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    wait_for_initialization()

    assert {:ok,
            %Anubis.MCP.Response{
              result: %{
                "content" => [
                  %{
                    "text" => json,
                    "type" => "text"
                  }
                ],
                "isError" => false
              },
              id: "req_" <> _,
              method: "tools/call",
              is_error: false
            }} = Sanbase.MCP.Client.call_tool("check_authentication", %{})

    assert {:ok,
            %{
              "id" => id,
              "email" => email,
              "auth_method" => "oauth",
              "subscriptions" => _subscriptions
            }} = Jason.decode(json)

    assert id == context.user.id
    assert email == context.user.email
  end

  test "unauthenticated - no authorization header", _context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    wait_for_initialization()

    assert {:ok,
            %Anubis.MCP.Response{
              result: %{
                "content" => [%{"text" => text, "type" => "text"}],
                "isError" => true
              },
              is_error: true
            }} = Sanbase.MCP.Client.call_tool("check_authentication", %{})

    assert text =~ "Unauthorized"
    assert text =~ "No Authorization header provided."
  end

  test "unauthenticated - invalid bearer token", _context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Bearer invalid_token_value",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    wait_for_initialization()

    assert {:ok,
            %Anubis.MCP.Response{
              result: %{
                "content" => [%{"text" => text, "type" => "text"}],
                "isError" => true
              },
              is_error: true
            }} = Sanbase.MCP.Client.call_tool("check_authentication", %{})

    assert text =~ "Unauthorized"
    assert text =~ "OAuth token is invalid or expired"
  end
end
