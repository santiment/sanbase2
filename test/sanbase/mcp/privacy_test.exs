defmodule Sanbase.MCP.PrivacyTest do
  use ExUnit.Case, async: true

  alias Sanbase.Accounts
  alias Sanbase.MCP.Privacy

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

  describe "mask_attrs/2" do
    test "hide_activity? = true: masks tool_name/params/user_agent/client; keeps counters" do
      masked = Accounts.masked_sentinel()
      attrs = base_attrs(7)

      out = Privacy.mask_attrs(attrs, true)

      assert out.tool_name == masked
      assert out.params == %{}
      assert out.user_agent == nil
      assert out.client == nil
      assert out.user_id == 7
      assert out.is_successful == true
      assert out.duration_ms == 42
      assert out.response_size_bytes == 123
      assert out.session_id == "sess-1"
      assert out.kind == "tool"
    end

    test "hide_activity? = true: masks non-nil error_message, leaves nil as nil" do
      masked = Accounts.masked_sentinel()

      assert %{error_message: ^masked} =
               Privacy.mask_attrs(%{base_attrs(7) | error_message: "boom"}, true)

      assert %{error_message: nil} =
               Privacy.mask_attrs(%{base_attrs(7) | error_message: nil}, true)
    end

    test "hide_activity? = false: attrs pass through unchanged" do
      attrs = base_attrs(7)
      assert Privacy.mask_attrs(attrs, false) == attrs
    end
  end
end
