defmodule Sanbase.Alert.Validation.NotificationChannel do
  @moduledoc false
  @notification_channels ["telegram_channel", "telegram", "email", "web_push", "webhook"]

  def valid_notification_channels, do: @notification_channels

  # TODO: Check if the key => value checks are needed
  def valid_notification_channel?(%{"webhook" => webhook_url}) when is_binary(webhook_url), do: :ok

  def valid_notification_channel?(%{webhook: webhook_url}) when is_binary(webhook_url), do: :ok

  def valid_notification_channel?(%{"telegram_channel" => telegram_channel}) when is_binary(telegram_channel), do: :ok

  def valid_notification_channel?(%{telegram_channel: telegram_channel}) when is_binary(telegram_channel), do: :ok

  def valid_notification_channel?(channel) when channel in @notification_channels, do: :ok

  def valid_notification_channel?(channels) when is_list(channels) do
    channels
    |> Enum.all?(&valid_notification_channel?(&1))
    |> case do
      true ->
        :ok

      false ->
        {:error,
         """
         #{inspect(channels)} is not a valid list of notification channels. The available notification channels are [#{Enum.join(@notification_channels, ", ")}]
         """}
    end
  end

  def valid_notification_channel?(channel) do
    {:error,
     """
     #{inspect(channel)} is not a valid notification channel. The available notification channels are [#{Enum.join(@notification_channels, ", ")}]
     """}
  end
end
