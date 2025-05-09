defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer

  require Logger

  alias Sanbase.DiscordBot.CommandHandler
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData

  @commands [
    %{
      name: "summary",
      description: "Summarize a channel or thread",
      options: [
        %{
          type: 7,
          name: "channel_or_thread",
          description: "channel or thread",
          required: true
        },
        %{
          type: 3,
          name: "from_dt",
          description: "From date",
          required: true,
          autocomplete: true
        },
        %{
          type: 3,
          name: "to_dt",
          description: "To date",
          required: true,
          autocomplete: true
        }
      ]
    },
    %{
      name: "query",
      description: "Run new query"
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

  def commands, do: @commands

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    cond do
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
             "summary"
           ] do
    warm_up(interaction)

    case command do
      cmd when cmd in ["summary"] ->
        case CommandHandler.discord_metadata(interaction) do
          %{user_is_team_member: true} = metadata ->
            CommandHandler.handle_interaction(command, interaction, metadata)
            |> handle_response(cmd, interaction, metadata, retry: false)

          _ ->
            CommandHandler.access_denied(interaction)
        end

      _ ->
        :noop
    end
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: custom_id}} =
          interaction,
        _ws_state
      }) do
    warm_up(interaction)
    [command, id] = String.split(custom_id, "_")

    cond do
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

  defp log(msg_or_interaction, log_text, opts \\ [])

  defp log(%Nostrum.Struct.Message{} = msg, log_text, opts) do
    params = %{
      channel: to_string(msg.channel_id),
      guild: to_string(msg.guild_id),
      discord_user_id: to_string(msg.author.id),
      discord_user_handle: msg.author.username <> msg.author.discriminator
    }

    log_msg = "[id=#{msg.id}] #{log_text} msg.content=#{msg.content} metadata=#{inspect(params)}"

    stacktrace = Keyword.get(opts, :stacktrace)

    log_msg =
      if stacktrace,
        do: log_msg <> " stacktrace=#{Exception.format_stacktrace(stacktrace)}",
        else: log_msg

    if Keyword.get(opts, :type, :info) do
      Logger.info(log_msg)
    else
      Logger.error(log_msg)
    end
  end

  defp log(%Nostrum.Struct.Interaction{} = interaction, log_text, opts) do
    params = %{
      channel: to_string(interaction.channel_id),
      guild: to_string(interaction.guild_id),
      discord_user_id: to_string(interaction.user.id),
      discord_user_handle: interaction.user.username <> interaction.user.discriminator
    }

    log_msg =
      "[id=#{interaction.id}] [#{inspect(interaction.data)}] #{log_text} metadata=#{inspect(params)}"

    stacktrace = Keyword.get(opts, :stacktrace)

    log_msg =
      if stacktrace,
        do: log_msg <> " stacktrace=#{Exception.format_stacktrace(stacktrace)}",
        else: log_msg

    if Keyword.get(opts, :type, :info) do
      Logger.info(log_msg)
    else
      Logger.error(log_msg)
    end
  end

  defp retry(command, interaction, metadata) do
    CommandHandler.handle_interaction(command, interaction, metadata)
    |> handle_response(command, interaction, metadata, retry: false)
  end

  defp handle_response(response, command, interaction, metadata, opts) do
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
          retry(command, interaction, metadata)
        end

      {:error, error} ->
        Logger.error("COMMAND ERROR #{command_insp} #{inspect(params)} #{inspect(error)}")
    end
  end

  defp warm_up(msg_or_interaction, retries \\ 3) do
    t1 = System.monotonic_time(:millisecond)
    log(msg_or_interaction, "WARM UP STARTING...")

    task = Task.async(fn -> Nostrum.Api.get_current_user() end)

    case Task.yield(task, 2000) || Task.shutdown(task) do
      nil ->
        log(msg_or_interaction, "WARM UP ERROR: Timeout reached.", type: :error)

        if retries > 0 do
          log(msg_or_interaction, "WARM UP TIMEOUT: Retrying...", type: :error)

          warm_up(msg_or_interaction, retries - 1)
        else
          log(msg_or_interaction, "WARM UP TIMEOUT: No more retries.", type: :error)
        end

      {:ok, result} ->
        # handle the result
        handle_result(result, msg_or_interaction, retries)
    end

    t2 = System.monotonic_time(:millisecond)
    log(msg_or_interaction, "Time spent warming up #{t2 - t1}ms.")
  end

  defp handle_result({:ok, _}, msg_or_interaction, _retries) do
    log(msg_or_interaction, "WARM UP SUCCESS")
  end

  defp handle_result({:error, :timeout}, msg_or_interaction, _retries) do
    log(msg_or_interaction, "WARM UP TIMEOUT. Restart Ratelimiter", type: :error)
  end

  defp handle_result(error, msg_or_interaction, retries) when retries > 0 do
    log(msg_or_interaction, "Unexpected error in WARM UP: #{inspect(error)}. Retrying...",
      type: :error
    )

    warm_up(msg_or_interaction, retries - 1)
  end

  defp handle_result(error, msg_or_interaction, _retries) do
    log(msg_or_interaction, "WARM UP ERROR: #{inspect(error)}. No more retries.", type: :error)
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
