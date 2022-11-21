defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer

  require Logger

  alias Sanbase.Discord.CommandHandler
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData

  @env Application.compile_env(:sanbase, :env)
  @commands [
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
    }
  ]

  @dev_commands [
    %{
      name: "auth",
      description: "Authenticate"
    },
    %{
      name: "admin-role",
      description: "Add/Change admin role",
      options: [
        %{
          # ApplicationCommandType::ROLE
          type: 8,
          name: "role",
          description: "role",
          required: true
        }
      ]
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

  def handle_event({:READY, _data, _ws_state}) do
    commands = if @env == :prod, do: @commands, else: @commands ++ @dev_commands

    Nostrum.Api.bulk_overwrite_global_application_commands(commands)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: command}} = interaction,
        _ws_state
      })
      when command in ["query", "help", "auth", "create-admin", "remove-admin", "list", "run"] do
    CommandHandler.handle_interaction(command, interaction)
    |> handle_response(command, interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: custom_id}} =
          interaction,
        _ws_state
      }) do
    [command, panel_id] = String.split(custom_id, "_")

    if command in ["rerun", "pin", "unpin", "show"] do
      CommandHandler.handle_interaction(command, interaction, panel_id)
      |> handle_response({command, panel_id}, interaction)
    else
      :noop
    end
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

  def retry({command, panel_id}, interaction) do
    CommandHandler.handle_interaction(command, interaction, panel_id)
    |> handle_response(command, interaction, retry: false)
  end

  def retry(command, interaction) do
    CommandHandler.handle_interaction(command, interaction)
    |> handle_response(command, interaction, retry: false)
  end

  def handle_response(response, command, interaction, opts \\ []) do
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

      {:error, {:stream_error, :closed} = error} ->
        Logger.error("COMMAND ERROR #{command} #{inspect(params)} #{inspect(error)}")

        if Keyword.get(opts, :retry, true) do
          retry(command, interaction)
        end

      {:error, error} ->
        Logger.error("COMMAND ERROR #{command} #{inspect(params)} #{inspect(error)}")
    end
  end
end
