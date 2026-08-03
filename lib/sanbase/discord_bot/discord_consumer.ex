defmodule Sanbase.DiscordConsumer do
  use Nostrum.Consumer

  require Logger

  alias Sanbase.DiscordBot.CommandHandler
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    if msg_contains_bot_mention?(msg) do
      case CommandHandler.handle_command("mention", msg) do
        {:ok, _} -> log(msg, "MENTION COMMAND SUCCESS")
        :ok -> log(msg, "MENTION COMMAND SUCCESS")
        result -> log(msg, "MENTION COMMAND RESULT #{inspect(result)}")
      end

      :ok
    else
      :ignore
    end
  end

  def handle_event({:READY, _data, _ws_state}) do
    # The bot registers no slash commands - it is driven by @mentions and by the
    # feedback buttons. Overwriting with an empty list also unregisters any
    # commands that were registered by previous versions.
    Nostrum.Api.ApplicationCommand.bulk_overwrite_global_commands([])
  end

  def handle_event({
        :INTERACTION_CREATE,
        %Interaction{data: %ApplicationCommandInteractionData{custom_id: custom_id}} =
          interaction,
        _ws_state
      }) do
    # Discord invalidates the interaction token if we do not respond within 3
    # seconds, so nothing slow may run before `handle_interaction/3` answers.
    [command, thread_id] = String.split(custom_id, "_")

    if command in ["up", "down"] do
      CommandHandler.handle_interaction(command, interaction, thread_id)
    else
      :noop
    end
  end

  # Unhandled events are ignored by the default `handle_event(_)` clause
  # injected by `use Nostrum.Consumer`.

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
end
