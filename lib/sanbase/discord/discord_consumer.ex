defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer

  alias Sanbase.Discord.CommandHandler

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case CommandHandler.is_command?(msg) do
      true -> CommandHandler.handle_command(msg)
      _ -> :ignore
    end
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(event) do
    :noop
  end
end
