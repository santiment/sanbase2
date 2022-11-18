defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer

  require Logger

  alias Sanbase.Discord.CommandHandler
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    with true <- CommandHandler.is_command?(msg.content),
         {:ok, command} <- CommandHandler.try_extracting_command(msg.content) do
      CommandHandler.handle_command(command, msg)
      |> handle_msg_response(command, msg)
    else
      {:error, :invalid_command} ->
        CommandHandler.handle_command(:invalid_command, msg)
        CommandHandler.handle_command("help", msg)

      false ->
        :ignore
    end
  end

  def handle_event({:READY, data, _ws_state}) do
    commands = [
      %{
        name: "help",
        description: "How to run sql query"
      },
      %{
        name: "query",
        description: "Run SQL query"
      },
      %{
        name: "list",
        description: "List pinned sql queries"
      },
      %{
        name: "auth",
        description: "Authenticate"
      },
      %{
        name: "create-admin",
        description: "Create admin",
        options: [
          %{
            # ApplicationCommandType::USER
            type: 6,
            name: "user",
            description: "user",
            required: true
          }
        ]
      },
      %{
        name: "remove-admin",
        description: "Remove admin",
        options: [
          %{
            # ApplicationCommandType::USER
            type: 6,
            name: "user",
            description: "user",
            required: true
          }
        ]
      }
    ]

    Nostrum.Api.bulk_overwrite_global_application_commands(commands) |> IO.inspect()
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "query"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("show_modal", interaction)
    |> handle_response("show_modal", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "help"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("help", interaction)
    |> handle_response("help", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "auth"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("auth", interaction)
    |> handle_response("auth", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "create-admin"}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("create-admin", interaction)
    |> handle_response("create-admin", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "remove-admin"}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("remove-admin", interaction)
    |> handle_response("remove-admin", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: "list"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("list", interaction)
    |> handle_response("list", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "run_sql_modal"}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("run", interaction)
    |> handle_response("run", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "pin" <> panel_id}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("pin", interaction, panel_id)
    |> handle_response("pin" <> panel_id, interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "unpin" <> panel_id}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("unpin", interaction, panel_id)
    |> handle_response("unpin" <> panel_id, interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "show" <> panel_id}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("show", interaction, panel_id)
    |> handle_response("show" <> panel_id, interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "rerun" <> panel_id}} =
          interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("rerun", interaction, panel_id)
    |> handle_response("rerun" <> panel_id, interaction)
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  def handle_msg_response(response, command, msg) do
    params = %{
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
      discord_user_id: to_string(msg.author.id),
      discord_user_handle: msg.author.username <> msg.author.discriminator
    }

    case response do
      {:ok, _} ->
        Logger.info("MSG COMMAND SUCCESS #{command} #{msg.content} #{inspect(params)}")

      :ok ->
        Logger.info("MSG COMMAND SUCCESS #{command} #{msg.content} #{inspect(params)}")

      {:error, error} ->
        Logger.error(
          "MSG COMMAND ERROR #{command} #{msg.content} #{inspect(params)} #{inspect(error)}"
        )
    end
  end

  def handle_response(response, command, interaction) do
    params = %{
      channel: to_string(interaction.channel_id),
      guild: to_string(interaction.guild_id),
      discord_user_id: to_string(interaction.user.id),
      discord_user_handle: interaction.user.username <> interaction.user.discriminator
    }

    case response do
      :ok ->
        Logger.info("COMMAND SUCCESS #{command} #{inspect(params)}")

      {:ok} ->
        Logger.info("COMMAND SUCCESS #{command} #{inspect(params)}")

      {:ok, _} ->
        Logger.info("COMMAND SUCCESS #{command} #{inspect(params)}")

      {:error, error} ->
        Logger.error("COMMAND ERROR #{command} #{inspect(params)} #{inspect(error)}")
    end
  end
end
