defmodule Sanbase.Notifications.Discord do
  @moduledoc ~s"""
  Send notification to Discord and handle the response
  """
  require Mockery.Macro
  require Logger

  @discord_message_size_limit 1900

  @type json :: String.t()

  @doc ~s"""
  Send the payload to Discord. Handle the response and log accordingly
  """
  @spec send_notification(String.t(), String.t(), json) :: :ok | {:error, String.t()}
  def send_notification(webhook, signal_name, payload) do
    case http_client().post(webhook, payload, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{} = resp} ->
        Logger.error(
          "Cannot publish #{signal_name} signal in Discord: HTTP Response: #{inspect(resp)}"
        )

        {:error, "Cannot publish #{signal_name} signal in Discord"}

      {:error, error} ->
        Logger.error("Cannot publish #{signal_name} in Discord. Reason: " <> inspect(error))
        {:error, "Cannot publish #{signal_name} signal in Discord"}
    end
  end

  @doc ~s"""
  Encode the payload and the username that will be used as the author of the Disord message.
  The result is ready to be passed to `send_notification/3`
  """
  @spec encode!([String.t()], String.t()) :: String.t() | no_return
  def encode!([], _), do: nil

  def encode!(payload, publish_user) do
    payload =
      payload
      |> Enum.join("\n")

    Jason.encode!(%{content: payload, username: publish_user})
  end

  @doc ~s"""
  Discord currently has limit of 2000 chars.
  Groups a list of messages into groups which combined doesn't exceed `message_size_limit`
  """
  @spec group_messages([any()]) :: [any()]
  def group_messages(messages) do
    {groups, last} =
      messages
      |> Enum.reduce({[], []}, fn el, {acc, tmp_acc} ->
        if messages_len(el) + messages_len(tmp_acc) > @discord_message_size_limit do
          {acc ++ [tmp_acc], [el]}
        else
          {acc, tmp_acc ++ [el]}
        end
      end)

    groups ++ [last]
  end

  # Private functions
  defp http_client() do
    Mockery.Macro.mockable(HTTPoison)
  end

  defp messages_len([]), do: 0
  defp messages_len(str) when is_binary(str), do: String.length(str)

  defp messages_len(list) when is_list(list) do
    list
    |> Enum.map(&String.length/1)
    |> Enum.sum()
  end
end
