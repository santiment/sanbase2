defprotocol Sanbase.Signal do
  def send(trigger, user)
end

defimpl Sanbase.Signal, for: Any do
  def send(%{channel: "telegram"} = trigger, %Sanbase.Auth.User{} = user) do
    Sanbase.Telegram.send_message(user, to_string(trigger))
  end
end
