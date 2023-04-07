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
      description: "Show help info and commands"
    },
    %{
      name: "query",
      description: "Run new query"
    },
    %{
      name: "list",
      description: "List pinned queries"
    },
    %{
      name: "chart",
      description: "Create a Sanbase metric chart",
      options: [
        %{
          type: 3,
          name: "project",
          description: "project",
          required: true,
          autocomplete: true
        },
        %{
          type: 3,
          name: "metric",
          description: "metric",
          required: true,
          autocomplete: true
        }
      ]
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

  #  @local_bot_id 1_039_543_550_326_612_009

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    cond do
      CommandHandler.is_command?(msg.content) -> do_handle_command(msg)
      CommandHandler.is_ai_command?(msg.content) -> CommandHandler.handle_command("ai", msg)
      CommandHandler.is_docs_command?(msg.content) -> CommandHandler.handle_command("docs", msg)
      CommandHandler.is_index_command?(msg.content) -> CommandHandler.handle_command("gi", msg)
      CommandHandler.is_ask_command?(msg.content) -> CommandHandler.handle_command("ga", msg)
      msg_contains_bot_mention?(msg) -> CommandHandler.handle_command("mention", msg)
      true -> :ignore
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
      when command in ["query", "help", "auth", "create-admin", "remove-admin", "list", "chart"] do
    CommandHandler.handle_interaction(command, interaction)
    |> handle_response(command, interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "run"}} = interaction,
        _ws_state
      }) do
    CommandHandler.handle_interaction("run", interaction)
    |> handle_response("run", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: custom_id}} =
          interaction,
        _ws_state
      }) do
    [command, id] = String.split(custom_id, "_")

    cond do
      command in ["rerun", "pin", "unpin", "show"] ->
        panel_id = id

        CommandHandler.handle_interaction(command, interaction, panel_id)
        |> handle_response({command, panel_id}, interaction)

      command in ["up", "down"] ->
        thread_id = id
        CommandHandler.handle_interaction(command, interaction, thread_id)

      true ->
        :noop
    end
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  defp msg_contains_bot_mention?(msg) do
    msg.mentions
    |> Enum.any?(&(&1.id == CommandHandler.bot_id()))
  end

  defp handle_msg_response(response, command, msg) do
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

  defp do_handle_command(msg) do
    with {:ok, name, sql} <- CommandHandler.parse_message_command(msg.content) do
      CommandHandler.handle_command("run", name, sql, msg)
      |> handle_msg_response("run", msg)
    else
      {:error, :invalid_command} ->
        CommandHandler.handle_command("invalid_command", msg)
        CommandHandler.handle_command("help", msg)

      false ->
        :ignore
    end
  end

  defp retry({command, panel_id}, interaction) do
    CommandHandler.handle_interaction(command, interaction, panel_id)
    |> handle_response(command, interaction, retry: false)
  end

  defp retry(command, interaction) do
    CommandHandler.handle_interaction(command, interaction)
    |> handle_response(command, interaction, retry: false)
  end

  defp handle_response(response, command, interaction, opts \\ []) do
    params = %{
      channel: to_string(interaction.channel_id),
      guild: to_string(interaction.guild_id),
      discord_user_id: to_string(interaction.user.id),
      discord_user_handle: interaction.user.username <> interaction.user.discriminator
    }

    command_insp = inspect(command)

    case response do
      :ok ->
        Logger.info("COMMAND SUCCESS #{command_insp} #{inspect(params)}")

      {:ok} ->
        Logger.info("COMMAND SUCCESS #{command_insp} #{inspect(params)}")

      {:ok, _} ->
        Logger.info("COMMAND SUCCESS #{command_insp} #{inspect(params)}")

      {:error, {:stream_error, :closed} = error} ->
        Logger.error("COMMAND ERROR #{command_insp} #{inspect(params)} #{inspect(error)}")

        if Keyword.get(opts, :retry, true) do
          retry(command, interaction)
        end

      {:error, error} ->
        Logger.error("COMMAND ERROR #{command_insp} #{inspect(params)} #{inspect(error)}")
    end
  end
end
