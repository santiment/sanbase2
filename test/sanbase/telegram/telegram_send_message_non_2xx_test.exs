defmodule Sanbase.TelegramSendMessageNon2xxTest do
  # SANBASE-BACKEND-PROD-7QV: a non-200 reply must be {:error, binary}
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Sanbase.Telegram

  for status <- [429, 500, 502, 503] do
    @status status

    test "status #{status} returns {:error, binary}, not {:ok, %Tesla.Env{}}" do
      Tesla.Mock.mock(fn %{method: :post} ->
        %Tesla.Env{
          status: @status,
          body: "<html><head><title>#{@status}</title></head></html>"
        }
      end)

      capture_log(fn ->
        result = Telegram.send_message_to_chat_id("@sanr_signals", "text")
        assert {:error, error} = result
        assert is_binary(error)
      end)
    end
  end

  test "a 200 response returns the raw body binary that can be JSON decoded" do
    Tesla.Mock.mock(fn %{method: :post} ->
      %Tesla.Env{status: 200, body: ~s({"ok":true,"result":{"message_id":123}})}
    end)

    assert {:ok, body} = Telegram.send_message_to_chat_id("@sanr_signals", "text")
    assert is_binary(body)
    assert Jason.decode!(body)["result"]["message_id"] == 123
  end
end
