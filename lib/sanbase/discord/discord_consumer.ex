defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer

  alias Sanbase.Discord.CommandHandler
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case CommandHandler.is_command?(msg) do
      true -> CommandHandler.handle_command(msg)
      _ -> :ignore
    end
  end

  def handle_event({:READY, data, _ws_state}) do
    guild_ids = data.guilds |> Enum.map(& &1.id)

    guild_ids
    |> Enum.each(fn guild_id ->
      Nostrum.Api.create_guild_application_command(guild_id, %{
        name: "query",
        description: "Run SQL query"
      })

      Nostrum.Api.create_guild_application_command(guild_id, %{
        name: "help",
        description: "How to run sql query"
      })
    end)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "query"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("show_modal", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "help"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("help", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "run_sql_modal"}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("run", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "pin" <> panel_id}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("pin", interaction, panel_id)
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(event) do
    :noop
  end
end
