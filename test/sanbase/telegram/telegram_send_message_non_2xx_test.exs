defmodule Sanbase.TelegramSendMessageNon2xxTest do
  @moduledoc ~s"""
  Regression test for SANBASE-BACKEND-PROD-7QV:
  ArgumentError: 1st argument: not an iodata term, in :erlang.iolist_to_binary/1
  from Jason.decode!/2 in Sanbase.Alert.Any.send_preview_image/3.

  Before e1759070c, `send_message_to_chat_id/3` ended with a catch-all
  `error -> ...; error` clause that returned the raw `{:ok, %Tesla.Env{status: 429 | 5xx}}`.
  `maybe_send_preview_image_as_reply/4` matched it as `{:ok, response}` and called
  `Jason.decode!(%Tesla.Env{})`, which raises "not an iodata term".

  Any non-200 reply must come back as `{:error, binary}` so no `{:ok, %Tesla.Env{}}`
  ever reaches the preview image code.
  """
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
