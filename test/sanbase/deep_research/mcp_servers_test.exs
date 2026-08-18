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
    test "sends the key the caller already has" do
      user = insert(:user)
      {:ok, apikey} = Apikey.generate_apikey(user)

      assert [%{"headers" => headers}] =
               McpServers.build([entry(%{auth: :santiment_apikey})], user)

      assert headers == %{"Authorization" => "Apikey #{apikey}"}
    end

    test "generates a key for a caller who has none, and sends that one" do
      user = insert(:user)
      assert {:ok, []} = Apikey.apikeys_list(user)

      assert [%{"headers" => headers}] =
               McpServers.build([entry(%{auth: :santiment_apikey})], user)

      # The key the user now owns is the key that was sent — not merely "an Apikey".
      assert {:ok, [apikey]} = Apikey.apikeys_list(user)
      assert headers == %{"Authorization" => "Apikey #{apikey}"}
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

  describe "a malformed catalog entry" do
    # Entries come from runtime.exs, so an unset env var can leave :url nil. Raising
    # here would crash the stream task, park the turn :paused, and make Continue
    # repeat the crash — drop the server and run without it instead.
    test "is dropped, whichever of label/url is missing" do
      for attrs <- [%{url: nil}, %{label: nil}, %{auth: :bearer, token: "t", url: nil}] do
        log = capture_log(fn -> assert McpServers.build([entry(attrs)], insert(:user)) == [] end)

        assert log =~ "dropping MCP server \"santiment\""
        assert log =~ "label and url must both be strings"
      end
    end

    test "does not take the well-formed entries with it" do
      capture_log(fn ->
        assert [%{"label" => "Santiment"}] =
                 McpServers.build([entry(%{key: "broken", url: nil}), entry()], nil)
      end)
    end
  end
end
