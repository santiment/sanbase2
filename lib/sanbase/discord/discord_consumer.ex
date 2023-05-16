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

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    cond do
      CommandHandler.is_command?(msg.content) ->
        do_handle_command(msg)

      CommandHandler.is_ai_command?(msg.content) ->
        warm_up(msg)
        result = CommandHandler.handle_command("ai", msg)
        log(msg, "ai COMMAND RESULT #{inspect(result)}")
        :ok

      CommandHandler.is_docs_command?(msg.content) ->
        warm_up(msg)
        result = CommandHandler.handle_command("docs", msg)
        log(msg, "docs COMMAND RESULT #{inspect(result)}")
        :ok

      msg_contains_bot_mention?(msg) ->
        warm_up(msg)

        CommandHandler.handle_command("mention", msg)
        |> case do
          {:ok, _} -> log(msg, "MENTION COMMAND SUCCESS")
          :ok -> log(msg, "MENTION COMMAND SUCCESS")
          result -> log(msg, "MENTION COMMAND RESULT #{inspect(result)}")
        end

        :ok

      true ->
        :ignore
    end
  end

  def handle_event({:READY, _data, _ws_state}) do
    Nostrum.Api.bulk_overwrite_global_application_commands(@commands)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{name: command}} = interaction,
        _ws_state
      })
      when command in [
             "query",
             "help",
             "list",
             "chart"
           ] do
    warm_up()

    CommandHandler.handle_interaction(command, interaction)
    |> handle_response(command, interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: "run"}} = interaction,
        _ws_state
      }) do
    warm_up()

    CommandHandler.handle_interaction("run", interaction)
    |> handle_response("run", interaction)
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: custom_id}} =
          interaction,
        _ws_state
      }) do
    warm_up()
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

  defp log(msg, log_text, opts \\ []) do
    params = %{
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
      discord_user_id: to_string(msg.author.id),
      discord_user_handle: msg.author.username <> msg.author.discriminator
    }

    log_msg = "[id=#{msg.id}] #{log_text} msg.content=#{msg.content} metadata=#{inspect(params)}"

    if Keyword.get(opts, :type, :info) do
      Logger.info(log_msg)
    else
      Logger.error(log_msg)
    end
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

  defp warm_up() do
    Nostrum.Api.get_current_user()
  end

  defp warm_up(msg) do
    t1 = System.monotonic_time(:millisecond)

    Nostrum.Api.get_current_user()
    |> case do
      {:ok, _} ->
        log(msg, "WARM UP SUCCESS")

      {:error, :timeout} ->
        log(msg, "WARM UP TIMEOUT. Restart Ratelimiter", type: :error)
        {:ok, pid} = restart_ratelimiter()
        log(msg, "WARM UP TIMEOUT. Ratelimiter pid: #{pid}", type: :error)

      error ->
        log(msg, "WARM UP ERROR #{inspect(error)}", type: :error)
    end

    t2 = System.monotonic_time(:millisecond)
    log(msg, "Time spent warming up #{t2 - t1}ms.")
  end

  def restart_ratelimiter() do
    supervisor_pid =
      Process.whereis(Ratelimiter)
      |> Process.info()
      |> Keyword.get(:dictionary)
      |> Keyword.get(:"$ancestors")
      |> List.first()

    :ok = Supervisor.terminate_child(supervisor_pid, Nostrum.Api.Ratelimiter)
    Supervisor.restart_child(supervisor_pid, Nostrum.Api.Ratelimiter)
  end
end
