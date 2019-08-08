defprotocol Sanbase.Signal do
  def send(user_trigger)
end

defimpl Sanbase.Signal, for: Any do
  require Logger

  def send(%{
        trigger: %{settings: %{triggered?: false}}
      }) do
    warn_msg = "Trying to send a signal that is not triggered."
    Logger.warn(warn_msg)
    {:error, warn_msg}
  end

  def send(%{trigger: %{settings: %{channel: "email"}}}), do: {:error, "Not implemented"}

  def send(%{
        user: %Sanbase.Auth.User{
          id: id,
          user_settings: %{settings: %{has_telegram_connected: false}}
        },
        trigger: %{settings: %{channel: "telegram"}}
      }) do
    Logger.warn("User with id #{id} does not have a telegram linked, so a signal cannot be sent.")

    {:error, "No telegram linked for #{id}"}
  end

  def send(%{
        id: id,
        user: user,
        trigger: %{
          settings: %{channel: "telegram", triggered?: true, payload: payload_map}
        }
      })
      when is_map(payload_map) do
    payload_map
    |> Enum.map(fn {slug, payload} ->
      {slug, Sanbase.Telegram.send_message(user, extend_payload(payload, id))}
    end)
  end

  defp extend_payload(payload, user_trigger_id) do
    """
    #{payload}
    The signal was triggered by #{SanbaseWeb.Endpoint.show_signal_url(user_trigger_id)}
    """
  end
end
