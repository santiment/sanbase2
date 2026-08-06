defmodule Sanbase.Alert.Validation.NotificationChannelTest do
  use ExUnit.Case, async: true

  alias Sanbase.Alert.Validation.NotificationChannel

  describe "valid_notification_channel?/1 with bare strings" do
    test "telegram is valid" do
      assert NotificationChannel.valid_notification_channel?("telegram") == :ok
    end

    test "email is valid" do
      assert NotificationChannel.valid_notification_channel?("email") == :ok
    end

    test "web_push is valid" do
      assert NotificationChannel.valid_notification_channel?("web_push") == :ok
    end

    test "bare \"webhook\" is rejected (carries no URL)" do
      assert {:error, msg} = NotificationChannel.valid_notification_channel?("webhook")
      assert msg =~ "is not a valid notification channel"
    end

    test "bare \"telegram_channel\" is rejected (carries no chat id)" do
      assert {:error, msg} = NotificationChannel.valid_notification_channel?("telegram_channel")
      assert msg =~ "is not a valid notification channel"
    end
  end

  describe "valid_notification_channel?/1 with map form" do
    test "atom-key webhook with binary URL is valid" do
      assert NotificationChannel.valid_notification_channel?(%{webhook: "https://example.com/x"}) ==
               :ok
    end

    test "string-key webhook with binary URL is valid" do
      assert NotificationChannel.valid_notification_channel?(%{
               "webhook" => "https://example.com/x"
             }) == :ok
    end

    test "atom-key telegram_channel with binary id is valid" do
      assert NotificationChannel.valid_notification_channel?(%{telegram_channel: "@my_channel"}) ==
               :ok
    end

    test "string-key telegram_channel with binary id is valid" do
      assert NotificationChannel.valid_notification_channel?(%{
               "telegram_channel" => "@my_channel"
             }) == :ok
    end

    test "webhook map with non-binary URL is rejected" do
      assert {:error, _} = NotificationChannel.valid_notification_channel?(%{webhook: nil})
      assert {:error, _} = NotificationChannel.valid_notification_channel?(%{webhook: 123})
    end

    test "webhook URL policy is not checked here - it runs on create/update only" do
      assert NotificationChannel.valid_notification_channel?(%{webhook: "http://example.com/x"}) ==
               :ok
    end
  end

  describe "validate_webhook_urls/1" do
    test "valid https domain URLs are accepted" do
      assert NotificationChannel.validate_webhook_urls(%{webhook: "https://example.com/x"}) == :ok

      assert NotificationChannel.validate_webhook_urls([
               "telegram",
               %{"webhook" => "https://example.com/x"}
             ]) == :ok
    end

    test "non-webhook channels are ignored" do
      assert NotificationChannel.validate_webhook_urls(["telegram", "email"]) == :ok
      assert NotificationChannel.validate_webhook_urls(nil) == :ok
    end

    test "http URL is rejected" do
      assert {:error, error} =
               NotificationChannel.validate_webhook_urls(%{webhook: "http://example.com/x"})

      assert error =~ "must use the https scheme"

      assert {:error, _} =
               NotificationChannel.validate_webhook_urls([
                 "telegram",
                 %{"webhook" => "http://example.com/x"}
               ])
    end

    test "IP address host is rejected" do
      assert {:error, error} =
               NotificationChannel.validate_webhook_urls(%{webhook: "https://8.8.8.8/x"})

      assert error =~ "is an IP address"

      assert {:error, _} =
               NotificationChannel.validate_webhook_urls(%{
                 "webhook" => "https://[2606:4700::1111]/x"
               })
    end

    test "private IP or localhost is rejected" do
      assert {:error, _} =
               NotificationChannel.validate_webhook_urls(%{webhook: "https://127.0.0.1/x"})

      assert {:error, _} =
               NotificationChannel.validate_webhook_urls(%{webhook: "https://localhost/x"})
    end

    test "telegram_channel map with non-binary id is rejected" do
      assert {:error, _} =
               NotificationChannel.valid_notification_channel?(%{telegram_channel: nil})
    end
  end

  describe "valid_notification_channel?/1 with lists" do
    test "list of valid channels is valid" do
      channels = [
        "telegram",
        "email",
        %{"webhook" => "https://example.com/hook"}
      ]

      assert NotificationChannel.valid_notification_channel?(channels) == :ok
    end

    test "list containing bare \"webhook\" is rejected" do
      channels = ["telegram", "webhook"]
      assert {:error, msg} = NotificationChannel.valid_notification_channel?(channels)
      assert msg =~ "is not a valid list of notification channels"
    end

    test "list containing bare \"telegram_channel\" is rejected" do
      channels = ["email", "telegram_channel"]
      assert {:error, _} = NotificationChannel.valid_notification_channel?(channels)
    end
  end

  describe "valid_notification_channel?/1 with garbage" do
    test "unknown string is rejected" do
      assert {:error, _} = NotificationChannel.valid_notification_channel?("discord")
    end

    test "nil is rejected" do
      assert {:error, _} = NotificationChannel.valid_notification_channel?(nil)
    end

    test "integer is rejected" do
      assert {:error, _} = NotificationChannel.valid_notification_channel?(42)
    end
  end

  describe "valid_notification_channels/0" do
    test "advertises the full list of channel names" do
      channels = NotificationChannel.valid_notification_channels()
      assert "telegram" in channels
      assert "email" in channels
      assert "web_push" in channels
      assert "webhook" in channels
      assert "telegram_channel" in channels
    end
  end
end
