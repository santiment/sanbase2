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

  def send(%{
        user: %Sanbase.Auth.User{user_settings: nil} = user,
        trigger: %{settings: %{channel: "telegram"}}
      }) do
    Logger.warn(
      "User with id #{user.id} does not have a telegram linked, so a signal cannot be sent."
    )

    {:error, "No telegram linked for #{user.id}"}
  end

  def send(%{
        user: user,
        trigger: %{
          settings: %{channel: "telegram", triggered?: true, payload: payload}
        }
      }) do
    Sanbase.Telegram.send_message(user, payload)
  end
end
