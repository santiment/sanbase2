defmodule Sanbase.DeepResearch.McpServersTest do
  use Sanbase.DataCase, async: true

  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Accounts.Apikey
  alias Sanbase.DeepResearch.McpServers

  defp entry(attrs \\ %{}) do
    Map.merge(%{key: "santiment", label: "Santiment", url: "http://x/mcp", auth: :none}, attrs)
  end

  test "nothing enabled, nothing configured" do
    assert McpServers.build([], nil) == []
  end

  test "a server needing no auth carries no headers" do
    assert [config] = McpServers.build([entry()], nil)

    assert config == %{
             "name" => "Santiment",
             "label" => "Santiment",
             "url" => "http://x/mcp",
             "tools" => []
           }
  end

  describe ":santiment_apikey (only sanbase's own MCP)" do
    test "is authenticated with the caller's Santiment api key" do
      user = insert(:user)

      assert [%{"headers" => %{"Authorization" => header}}] =
               McpServers.build([entry(%{auth: :santiment_apikey})], user)

      assert header =~ "Apikey "
    end

    test "a catalog override wins, and no key is generated for the user" do
      user = insert(:user)
      server = entry(%{auth: :santiment_apikey, apikey_override: "override-key"})

      assert [%{"headers" => headers}] = McpServers.build([server], user)
      assert headers == %{"Authorization" => "Apikey override-key"}

      assert {:ok, []} = Apikey.apikeys_list(user)
    end

    test "is dropped when there is no user to resolve a key for" do
      assert McpServers.build([entry(%{auth: :santiment_apikey})], nil) == []
    end
  end

  describe ":bearer (a third-party server we hold a token for)" do
    test "sends the entry's token" do
      server = entry(%{auth: :bearer, token: "third-party-token"})

      assert [%{"headers" => headers}] = McpServers.build([server], nil)
      assert headers == %{"Authorization" => "Bearer third-party-token"}
    end

    test "is dropped when the entry carries no token" do
      assert McpServers.build([entry(%{auth: :bearer})], insert(:user)) == []
    end
  end

  test "an auth mode this module does not implement is dropped, not sent open" do
    log =
      capture_log(fn ->
        assert McpServers.build([entry(%{auth: :oauth})], insert(:user)) == []
      end)

    assert log =~ "unsupported auth :oauth"
  end
end
