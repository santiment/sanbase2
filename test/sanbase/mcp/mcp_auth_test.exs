defmodule SanbaseWeb.Graphql.MCPAuthTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2, wait_for_mcp_initialization: 0]

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

    # Generate an API key for the same user
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

    on_exit(fn ->
      if pid = Process.whereis(Sanbase.MCP.Client) do
        try do
          GenServer.stop(pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{user: user, bearer_token: token.value, apikey: apikey}
  end

  test "OAuth authentication", context do
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
    wait_for_mcp_initialization()

    assert Sanbase.MCP.Client |> Process.whereis() |> Process.alive?() == true

    registry_name = Anubis.Server.Registry.registry_name(Sanbase.MCP.Server)
    assert registry_name |> Process.whereis() |> Process.alive?() == true

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
            }} =
             try_few_times(fn -> Sanbase.MCP.Client.call_tool("check_authentication", %{}) end,
               attempts: 3,
               sleep: 250
             )

    assert {:ok,
            %{
              "id" => id,
              "email" => email,
              "auth_method" => "oauth",
              "apikey" => nil,
              "subscriptions" => _subscriptions
            }} = Jason.decode(json)

    assert id == context.user.id
    assert email == context.user.email
  end

  test "API key authentication with Apikey scheme", context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Apikey #{context.apikey}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    wait_for_mcp_initialization()

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
            }} =
             try_few_times(fn -> Sanbase.MCP.Client.call_tool("check_authentication", %{}) end,
               attempts: 3,
               sleep: 250
             )

    assert {:ok,
            %{
              "id" => id,
              "email" => email,
              "auth_method" => "apikey",
              "apikey" => obfuscated_apikey,
              "subscriptions" => _subscriptions
            }} = Jason.decode(json)

    assert id == context.user.id
    assert email == context.user.email
    # Obfuscated apikey preserves first 3 and last 3 chars
    assert String.slice(obfuscated_apikey, 0, 3) == String.slice(context.apikey, 0, 3)
    assert String.slice(obfuscated_apikey, -3, 3) == String.slice(context.apikey, -3, 3)
    assert String.contains?(obfuscated_apikey, "***")
  end

  test "API key authentication with Bearer Apikey scheme", context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Bearer Apikey #{context.apikey}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    wait_for_mcp_initialization()

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
            }} =
             try_few_times(fn -> Sanbase.MCP.Client.call_tool("check_authentication", %{}) end,
               attempts: 3,
               sleep: 250
             )

    assert {:ok,
            %{
              "id" => id,
              "auth_method" => "apikey"
            }} = Jason.decode(json)

    assert id == context.user.id
  end

  test "API key authentication with Bearer scheme", context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Bearer #{context.apikey}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    wait_for_mcp_initialization()

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
            }} =
             try_few_times(fn -> Sanbase.MCP.Client.call_tool("check_authentication", %{}) end,
               attempts: 3,
               sleep: 250
             )

    assert {:ok,
            %{
              "id" => id,
              "auth_method" => "apikey",
              "apikey" => obfuscated_apikey
            }} = Jason.decode(json)

    assert id == context.user.id
    assert String.slice(obfuscated_apikey, 0, 3) == String.slice(context.apikey, 0, 3)
    assert String.slice(obfuscated_apikey, -3, 3) == String.slice(context.apikey, -3, 3)
  end

  test "unauthenticated - no authorization header returns 401", _context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    # The client process starts but crashes when the initialize request gets 401
    Process.flag(:trap_exit, true)

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

    # The client should shut down because the 401 prevents initialization
    assert_receive {:EXIT, ^client, :shutdown}, 5000
  end

  test "unauthenticated - invalid bearer token returns 401", _context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    Process.flag(:trap_exit, true)

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

    # The client should shut down because the 401 prevents initialization
    assert_receive {:EXIT, ^client, :shutdown}, 5000
  end

  test "unauthenticated - invalid apikey returns 401", _context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    Process.flag(:trap_exit, true)

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Apikey invalid_apikey_value",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    # The client should shut down because the 401 prevents initialization
    assert_receive {:EXIT, ^client, :shutdown}, 5000
  end
end
