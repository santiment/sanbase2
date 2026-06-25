defmodule Sanbase.TelegramBot.MessageHandler do
  @moduledoc """
  Handles Telegram updates for the Q&A bot. Group-only - private messages are
  ignored.

  Reuses the Discord bot brains: `Sanbase.DiscordBot.AiServer` for answering and
  `Sanbase.DiscordBot.AiContext` for conversation history, votes and rate limits.
  Telegram identifiers are namespaced with a `tg_` prefix so they don't collide
  with Discord snowflake ids in the shared `ai_context` table.

  Conversation model (Discord-thread analogue via reply chains):
  - `@mention <question>` starts a NEW conversation - the bot answers as a reply
    to the question. Conversation id: `tg_<chat_id>_m<message_id>`.
  - Replying to any bot answer CONTINUES that conversation (no mention needed).
    Every sent answer is recorded in `telegram_bot_messages`, and the replied-to
    message id is looked up to find the conversation.
  - In forum supergroups, topics work too: a mention in General opens a topic
    (context per topic, id `tg_<chat_id>_<topic_id>`), and any message inside a
    topic that triggers the bot continues that topic's context.
  """

  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.AiServer
  alias Sanbase.DiscordBot.Utils
  alias Sanbase.TelegramBot.Api
  alias Sanbase.TelegramBot.BotMessage

  # Telegram hard limit is 4096
  @max_message_length 4000
  @typing_interval 5_000
  # Telegram topic name limit is 128
  @max_topic_name_length 90

  def handle_update(%{"message" => message}, bot), do: handle_message(message, bot)

  def handle_update(%{"callback_query" => callback_query}, _bot),
    do: handle_callback_query(callback_query)

  def handle_update(_update, _bot), do: :ignore

  # Private functions

  defp handle_message(%{"text" => text, "from" => %{"is_bot" => false}} = message, bot)
       when is_binary(text) do
    case message["chat"]["type"] do
      type when type in ["group", "supergroup"] ->
        handle_group_message(message, text, bot)

      "private" ->
        Api.send_message(
          message["chat"]["id"],
          "👋 I only answer in the Santiment group. Mention me there to ask a question."
        )

      _ ->
        :ignore
    end
  end

  defp handle_message(_message, _bot), do: :ignore

  defp handle_group_message(message, text, bot) do
    mention = "@" <> bot.username
    mentioned? = String.contains?(String.downcase(text), String.downcase(mention))

    question =
      text
      |> String.replace(~r/@#{Regex.escape(bot.username)}/i, "")
      |> String.trim()

    cond do
      # Replying to a bot answer continues that conversation, mention not needed
      reply_to_bot?(message, bot) -> continue_conversation(message, question)
      mentioned? -> start_conversation(message, question)
      true -> :ignore
    end
  end

  defp reply_to_bot?(message, bot) do
    get_in(message, ["reply_to_message", "from", "id"]) == bot.id
  end

  defp continue_conversation(message, question) do
    chat_id = message["chat"]["id"]
    replied_to_id = get_in(message, ["reply_to_message", "message_id"])

    case BotMessage.conversation_for(chat_id, replied_to_id) do
      nil ->
        # Bot message predating the tracking table - treat as a new conversation
        start_conversation(message, question)

      conversation_id ->
        answer(message, question, conversation_id,
          message_thread_id: message["message_thread_id"],
          reply_to_message_id: message["message_id"]
        )
    end
  end

  defp start_conversation(message, "") do
    Api.send_message(
      message["chat"]["id"],
      "Please ask a question after mentioning me.",
      reply_to_message_id: message["message_id"],
      message_thread_id: message["message_thread_id"]
    )
  end

  defp start_conversation(message, question) do
    chat_id = message["chat"]["id"]

    cond do
      # Inside a forum topic - answer there, context is per topic
      message["is_topic_message"] && message["message_thread_id"] ->
        topic_id = message["message_thread_id"]

        answer(message, question, "tg_#{chat_id}_#{topic_id}",
          message_thread_id: topic_id,
          reply_to_message_id: message["message_id"]
        )

      # Forum group, question asked in General - open a new topic
      message["chat"]["is_forum"] ->
        case Api.create_forum_topic(chat_id, topic_name(question)) do
          {:ok, %{"message_thread_id" => topic_id}} ->
            Api.send_message(chat_id, "❓ #{question}", message_thread_id: topic_id)
            answer(message, question, "tg_#{chat_id}_#{topic_id}", message_thread_id: topic_id)

          {:error, _error} ->
            new_reply_chain_conversation(message, question)
        end

      # Plain group - new reply-chain conversation rooted at this message
      true ->
        new_reply_chain_conversation(message, question)
    end
  end

  defp new_reply_chain_conversation(message, question) do
    chat_id = message["chat"]["id"]
    conversation_id = "tg_#{chat_id}_m#{message["message_id"]}"

    answer(message, question, conversation_id, reply_to_message_id: message["message_id"])
  end

  defp answer(message, question, conversation_id, send_opts) do
    chat_id = message["chat"]["id"]

    typing_task =
      Task.async(fn -> keep_typing(chat_id, send_opts[:message_thread_id]) end)

    metadata = build_metadata(message, conversation_id)
    result = AiServer.answer(question, metadata)
    Task.shutdown(typing_task, :brutal_kill)

    case result do
      {:ok, ai_context, ai_server_response} ->
        send_answer(chat_id, ai_server_response, ai_context, conversation_id, send_opts)

      {:error, limit, time_left} when limit in [:eserverlimit, :eprolimit] ->
        Api.send_message(
          chat_id,
          "Daily question limit for this chat is reached. It will reset in #{time_left}.",
          send_opts
        )

      _other ->
        Api.send_message(
          chat_id,
          "Couldn't fetch information to answer your question.",
          send_opts
        )
    end
  end

  defp send_answer(chat_id, ai_server_response, ai_context, conversation_id, send_opts) do
    messages =
      ai_server_response
      |> build_content()
      |> Utils.split_message(@max_message_length)

    last_index = length(messages) - 1

    messages
    |> Enum.with_index()
    |> Enum.each(fn {text, index} ->
      opts =
        if index == last_index do
          Keyword.put(send_opts, :reply_markup, votes_keyboard(ai_context))
        else
          send_opts
        end

      case send_with_markdown_fallback(chat_id, text, opts) do
        {:ok, %{"message_id" => message_id}} ->
          # Record the sent message so future replies to it continue this conversation
          BotMessage.store(chat_id, message_id, conversation_id)

        _ ->
          :ok
      end
    end)
  end

  # Telegram's legacy Markdown parser rejects unbalanced */_, which LLM output
  # often contains - fall back to plain text on a 400 response
  defp send_with_markdown_fallback(chat_id, text, opts) do
    case Api.send_message(chat_id, text, Keyword.put(opts, :parse_mode, "Markdown")) do
      {:error, {:http_error, 400, _body}} -> Api.send_message(chat_id, text, opts)
      other -> other
    end
  end

  defp build_content(ai_server_response) do
    case ai_server_response["answer"] do
      %{"answer" => "DK"} ->
        "Couldn't fetch information to answer your question."

      answer ->
        case format_sources(answer["sources"]) do
          "" -> answer["answer"]
          sources -> "#{answer["answer"]}\n\n#{sources}"
        end
    end
  end

  defp format_sources(sources) when is_list(sources) do
    sources
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> case do
      "" -> ""
      sources_string -> "Sources:\n#{sources_string}"
    end
  end

  # Academy sources come as a comma-separated string of file paths and/or links
  defp format_sources(sources) when is_binary(sources) do
    sources
    |> String.split(~r/,\s+/)
    |> Enum.map(fn source ->
      source
      |> String.replace("src/docs/", "https://academy.santiment.net/")
      |> String.replace("index.md", "")
      |> String.replace("README.md", "https://github.com/santiment/sanpy")
      |> then(&Regex.replace(~r/\.md$/, &1, ""))
    end)
    |> Enum.filter(&String.starts_with?(&1, "http"))
    |> format_sources()
  end

  defp format_sources(_sources), do: ""

  defp votes_keyboard(%AiContext{} = ai_context) do
    votes_pos = Enum.count(ai_context.votes, fn {_user, vote} -> vote == 1 end)
    votes_neg = Enum.count(ai_context.votes, fn {_user, vote} -> vote == -1 end)

    %{
      inline_keyboard: [
        [
          %{text: "👍 #{votes_pos}", callback_data: "up_#{ai_context.id}"},
          %{text: "👎 #{votes_neg}", callback_data: "down_#{ai_context.id}"}
        ]
      ]
    }
  end

  defp handle_callback_query(%{"data" => data} = callback_query) do
    case String.split(data, "_") do
      [vote, context_id] when vote in ["up", "down"] ->
        voter =
          get_in(callback_query, ["from", "username"]) ||
            to_string(get_in(callback_query, ["from", "id"]))

        vote_value = if vote == "up", do: 1, else: -1
        {:ok, ai_context} = AiContext.add_vote(context_id, %{"tg:#{voter}" => vote_value})

        Api.answer_callback_query(callback_query["id"], "Thanks for the feedback!")

        if message = callback_query["message"] do
          Api.edit_message_reply_markup(
            message["chat"]["id"],
            message["message_id"],
            votes_keyboard(ai_context)
          )
        end

      _ ->
        Api.answer_callback_query(callback_query["id"])
    end
  end

  defp handle_callback_query(callback_query) do
    Api.answer_callback_query(callback_query["id"])
  end

  defp build_metadata(message, conversation_id) do
    chat = message["chat"]
    chat_name = chat["title"]

    %{
      discord_user: "tg:#{telegram_username(message["from"])}",
      guild_id: "tg_#{chat["id"]}",
      guild_name: chat_name,
      channel_id: to_string(chat["id"]),
      channel_name: chat_name,
      thread_id: conversation_id,
      thread_name: nil,
      msg_id: message["message_id"],
      user_is_pro: false
    }
  end

  defp telegram_username(from) do
    from["username"] || String.trim("#{from["first_name"]} #{from["last_name"]}")
  end

  defp keep_typing(chat_id, message_thread_id) do
    Api.send_chat_action(chat_id, message_thread_id: message_thread_id)
    Process.sleep(@typing_interval)
    keep_typing(chat_id, message_thread_id)
  end

  defp topic_name(question) do
    String.slice(question, 0, @max_topic_name_length)
  end
end
