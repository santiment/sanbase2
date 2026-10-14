defmodule Sanbase.TelegramSendMessageNon2xxTest do
  use ExUnit.Case, async: false

  alias Sanbase.Telegram

  @moduletag capture_log: true

  # Error bodies are not always JSON (e.g. a proxy error page)
  for {status, body, reason} <- [
        {400, ~s({"ok":false,"description":"Bad Request: chat not found"}),
         "Bad Request: chat not found"},
        {400, "<html>Bad Gateway</html>", "Bad request"},
        {404, nil, "Chat ID not found"}
      ] do
    test "status #{status} with body #{inspect(body)} gives the reason #{reason}" do
      Tesla.Mock.mock(fn %{method: :post} ->
        %Tesla.Env{status: unquote(status), body: unquote(body)}
      end)

      assert {:error, error} = Telegram.send_message_to_chat_id("@sanr_signals", "text")
      assert error =~ "Error status #{unquote(status)}. Reason: #{unquote(reason)}"
    end
  end
end
