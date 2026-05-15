defmodule Sanbase.MCP.PrivacyTest do
  use ExUnit.Case, async: true

  alias Sanbase.Accounts
  alias Sanbase.MCP.Privacy

  defp protected_id, do: Accounts.privacy_protected_user_ids() |> Enum.at(0)

  defp unprotected_id do
    Enum.find(10_000..20_000, fn id ->
      not MapSet.member?(Accounts.privacy_protected_user_ids(), id)
    end)
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
    test "masks tool_name, params, user_agent and client for protected users" do
      masked = Accounts.masked_sentinel()
      attrs = base_attrs(protected_id())

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

    test "masks error_message when present, leaves nil as nil" do
      masked = Accounts.masked_sentinel()

      assert %{error_message: ^masked} =
               Privacy.mask_attrs(%{base_attrs(protected_id()) | error_message: "boom"})

      assert %{error_message: nil} =
               Privacy.mask_attrs(%{base_attrs(protected_id()) | error_message: nil})
    end

    test "non-protected user: attrs pass through unchanged" do
      attrs = base_attrs(unprotected_id())
      assert Privacy.mask_attrs(attrs) == attrs
    end

    test "nil user_id (unauthenticated): attrs pass through unchanged" do
      attrs = base_attrs(nil)
      assert Privacy.mask_attrs(attrs) == attrs
    end
  end
end
