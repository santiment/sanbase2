defmodule Sanbase.MCP.PrivacyTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts
  alias Sanbase.MCP.Privacy

  setup do
    protected = insert(:user)
    unprotected = insert(:user)
    Sanbase.PrivacyCacheSeed.seed!([protected.id])
    {:ok, protected: protected, unprotected: unprotected}
  end

  defp base_attrs(user_id) do
    %{
      user_id: user_id,
      tool_name: "fetch_metric_data_tool",
      params: %{"metric" => "price_usd", "slug" => "bitcoin"},
      is_successful: true,
      error_message: nil,
      response_size_bytes: 123,
      duration_ms: 42,
      auth_method: :apikey,
      user_agent: "ChatGPT/1.0",
      client: "chatgpt",
      session_id: "sess-1",
      kind: "tool"
    }
  end

  describe "mask_attrs/1" do
    test "masks tool_name, params, user_agent and client for protected users", %{protected: user} do
      masked = Accounts.masked_sentinel()
      attrs = base_attrs(user.id)

      out = Privacy.mask_attrs(attrs)

      assert out.tool_name == masked
      assert out.params == %{}
      assert out.user_agent == nil
      assert out.client == nil
      # Non-sensitive counters/flags survive so we can still bill and measure.
      assert out.user_id == attrs.user_id
      assert out.is_successful == true
      assert out.duration_ms == 42
      assert out.response_size_bytes == 123
      assert out.session_id == "sess-1"
      assert out.kind == "tool"
    end

    test "masks error_message when present, leaves nil as nil", %{protected: user} do
      masked = Accounts.masked_sentinel()

      assert %{error_message: ^masked} =
               Privacy.mask_attrs(%{base_attrs(user.id) | error_message: "boom"})

      assert %{error_message: nil} =
               Privacy.mask_attrs(%{base_attrs(user.id) | error_message: nil})
    end

    test "non-protected user: attrs pass through unchanged", %{unprotected: user} do
      attrs = base_attrs(user.id)
      assert Privacy.mask_attrs(attrs) == attrs
    end

    test "nil user_id (unauthenticated): attrs pass through unchanged" do
      attrs = base_attrs(nil)
      assert Privacy.mask_attrs(attrs) == attrs
    end
  end
end
