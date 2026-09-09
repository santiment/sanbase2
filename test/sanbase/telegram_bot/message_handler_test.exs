defmodule Sanbase.TelegramBot.MessageHandlerTest do
  use ExUnit.Case, async: false

  alias Sanbase.TelegramBot.MessageHandler

  @santiment_chat %{"id" => -1_001_140_094_437, "title" => "Santiment"}
  @outside_chat %{"id" => -1_009_999_999_999, "title" => "Some Other Group"}

  setup do
    original = System.get_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS")
        value -> System.put_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS", value)
      end
    end)

    System.delete_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS")
    :ok
  end

  describe "allowed_chat?/1" do
    test "answers in Santiment's own groups by default" do
      assert MessageHandler.allowed_chat?(@santiment_chat)
    end

    test "refuses a group someone added the bot to themselves" do
      # Anyone can add a public bot to their own group. Left open, each new group
      # also got its own fresh daily quota.
      refute MessageHandler.allowed_chat?(@outside_chat)
    end

    test "the environment overrides the built-in list" do
      System.put_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS", "-1009999999999, -100888")

      assert MessageHandler.allowed_chat?(@outside_chat)
      refute MessageHandler.allowed_chat?(@santiment_chat)
    end

    test "a single star allows every chat" do
      System.put_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS", "*")

      assert MessageHandler.allowed_chat?(@outside_chat)
      assert MessageHandler.allowed_chat?(@santiment_chat)
    end

    test "an empty environment value falls back to the default list" do
      System.put_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS", "")

      assert MessageHandler.allowed_chat?(@santiment_chat)
      refute MessageHandler.allowed_chat?(@outside_chat)
    end
  end

  describe "allowed_chat_ids/0" do
    test "trims whitespace and drops empty entries" do
      System.put_env("TELEGRAM_QA_BOT_ALLOWED_CHAT_IDS", " -1001 , ,-1002 ")

      assert MessageHandler.allowed_chat_ids() == ["-1001", "-1002"]
    end
  end

  describe "handle_update/2" do
    test "ignores a message from a chat that is not allowed" do
      update = %{
        "message" => %{
          "text" => "@santiment_ai_bot what is MVRV?",
          "from" => %{"is_bot" => false, "username" => "someone"},
          "chat" => Map.put(@outside_chat, "type", "supergroup"),
          "message_id" => 1
        }
      }

      # No mention trigger reaches the AI server; the handler stops at the
      # allowlist. Sending the rejection notice needs no bot token in test.
      assert MessageHandler.handle_update(update, %{id: 42, username: "santiment_ai_bot"}) ==
               :ignore
    end

    test "ignores a non-triggering message in a chat that is not allowed" do
      update = %{
        "message" => %{
          "text" => "just chatting",
          "from" => %{"is_bot" => false, "username" => "someone"},
          "chat" => Map.put(@outside_chat, "type", "supergroup"),
          "message_id" => 1
        }
      }

      assert MessageHandler.handle_update(update, %{id: 42, username: "santiment_ai_bot"}) ==
               :ignore
    end
  end
end
