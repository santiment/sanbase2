defprotocol Sanbase.Signal do
  def send(user_trigger)
end

defimpl Sanbase.Signal, for: Any do
  require Logger

  def send(%{
        user: %Sanbase.Auth.User{user_settings: nil} = user,
        trigger: %{settings: %{channel: "telegram"}}
      }) do
    Logger.warn("User #{user.id} does not have a telegram linked, so a signal cannot be sent.")
  end

  def send(%{
        user: user,
        trigger: %{settings: %{channel: "telegram"} = trigger_settings}
      }) do
    Sanbase.Telegram.send_message(user, to_string(trigger_settings))
  end
end
