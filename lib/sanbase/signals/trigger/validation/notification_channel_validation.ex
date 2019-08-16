defmodule Sanbase.Signal.Validation.NotificationChannel do
  @notification_channels ["telegram", "email", "web_push"]

  def valid_notification_channels(), do: @notification_channels

  def valid_notification_channel?(channel) when channel in @notification_channels, do: :ok

  def valid_notification_channel?(channels) when is_list(channels) do
    channels
    |> Enum.all?(fn channel -> channel in @notification_channels end)
    |> case do
      true ->
        :ok

      false ->
        {:error,
         """
         #{inspect(channels)} is not a valid list of notification channels. The available notification channels are [#{
           @notification_channels |> Enum.join(", ")
         }]
         """}
    end
  end

  def valid_notification_channel?(channel) do
    {:error,
     """
     #{inspect(channel)} is not a valid notification channel. The available notification channels are [#{
       @notification_channels |> Enum.join(", ")
     }]
     """}
  end
end
