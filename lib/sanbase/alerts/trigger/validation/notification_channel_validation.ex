defmodule Sanbase.Alert.Validation.NotificationChannel do
  @notification_channels ["telegram_channel", "telegram", "email", "web_push", "webhook"]
  @bare_string_channels ["telegram", "email", "web_push"]

  def valid_notification_channels(), do: @notification_channels

  @doc ~s"""
  Extract the webhook URL from a channel entry, in both its stored
  (string-key) and loaded (atom-key) shape.
  """
  def webhook_url(%{"webhook" => url}) when is_binary(url), do: {:ok, url}
  def webhook_url(%{webhook: url}) when is_binary(url), do: {:ok, url}
  def webhook_url(_channel), do: :error

  @doc ~s"""
  Strict validation of the webhook URLs in a channel definition, applied on
  alert create/update. It is not part of `valid_notification_channel?/1` on
  purpose - that one also runs on every evaluation and would auto-disable
  legacy alerts whose other channels still work.
  """
  def validate_webhook_urls(channel) do
    channel
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      with {:ok, url} <- webhook_url(entry),
           {:error, _} = error <- Sanbase.Utils.Validation.valid_webhook_url?(url) do
        {:halt, error}
      else
        _ -> {:cont, :ok}
      end
    end)
  end

  # TODO: Check if the key => value checks are needed
  # The webhook checks are structural only - see validate_webhook_urls/1
  def valid_notification_channel?(%{"webhook" => webhook_url}) when is_binary(webhook_url),
    do: :ok

  def valid_notification_channel?(%{webhook: webhook_url}) when is_binary(webhook_url),
    do: :ok

  def valid_notification_channel?(%{"telegram_channel" => telegram_channel})
      when is_binary(telegram_channel),
      do: :ok

  def valid_notification_channel?(%{telegram_channel: telegram_channel})
      when is_binary(telegram_channel),
      do: :ok

  # "webhook" and "telegram_channel" require a URL / chat id and must be passed
  # as a map (e.g. %{"webhook" => url}). Bare strings carry no destination so
  # they are rejected — they previously slipped through and caused
  # FunctionClauseError in Sanbase.Alert.Any.send_to_channel/3.
  def valid_notification_channel?(channel) when channel in @bare_string_channels, do: :ok

  def valid_notification_channel?(channels) when is_list(channels) do
    # NOTE: each element returns either :ok or {:error, _}. Both are truthy,
    # so `Enum.all?` without an explicit `== :ok` check would always be true
    # and let bad channels slip through.
    if Enum.all?(channels, &(valid_notification_channel?(&1) == :ok)) do
      :ok
    else
      {:error,
       """
       #{inspect(channels)} is not a valid list of notification channels. The available notification channels are [#{@notification_channels |> Enum.join(", ")}]
       """}
    end
  end

  def valid_notification_channel?(channel) do
    {:error,
     """
     #{inspect(channel)} is not a valid notification channel. The available notification channels are [#{@notification_channels |> Enum.join(", ")}]
     """}
  end
end
