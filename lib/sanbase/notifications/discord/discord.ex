defmodule Sanbase.Notifications.Discord do
  @moduledoc ~s"""
  Send notification to Discord and handle the response
  """
  require Mockery.Macro
  require Logger

  @type json :: String.t()

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)

  @doc ~s"""
  Send the payload to Discord. Handle the response and log accordingly
  """
  @spec send_notification(String.t(), String.t(), json, map()) :: :ok | {:error, String.t()}
  def send_notification(_, _, _, opts \\ %{})

  def send_notification(_, _, _, %{retry_count: 5}), do: {:error, "Max retries reached"}

  def send_notification(webhook, signal_name, payload, opts) do
    case http_client().post(webhook, payload, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: code}} when code in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 429, body: body} = resp} ->
        body = body |> Jason.decode!()

        Logger.info(
          "Cannot publish #{signal_name} signal in Discord: HTTP Response: #{inspect(resp)}"
        )

        Process.sleep(body["retry_after"] + 1000)

        send_notification(
          webhook,
          signal_name,
          payload,
          Map.update(opts, :retry_count, 0, &(&1 + 1))
        )

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
  Encode the string payload, username and list of embeds.
  The result is ready to be passed to `send_notification/3`
  """
  @spec encode!(String.t(), String.t(), [any()]) :: String.t()
  def encode!(payload, publish_user, embeds) do
    Jason.encode!(%{content: payload, username: publish_user, embeds: embeds})
  end
end
