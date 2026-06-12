defmodule Sanbase.TelegramBot.Api do
  @moduledoc """
  Thin HTTP client for the Telegram Bot API used by the Q&A bot.

  Uses its own bot token (`TELEGRAM_QA_BOT_TOKEN`), distinct from the
  alerts bot token used by `Sanbase.Telegram`.
  """

  require Logger

  @base_url "https://api.telegram.org"

  def enabled?() do
    case token() do
      token when is_binary(token) and token != "" -> true
      _ -> false
    end
  end

  def get_me() do
    request("getMe", %{})
  end

  def delete_webhook() do
    request("deleteWebhook", %{})
  end

  def get_updates(offset, timeout_seconds \\ 30) do
    params = %{
      timeout: timeout_seconds,
      allowed_updates: ["message", "callback_query"]
    }

    params = if offset, do: Map.put(params, :offset, offset), else: params

    request("getUpdates", params, recv_timeout: (timeout_seconds + 10) * 1000)
  end

  def send_message(chat_id, text, opts \\ []) do
    %{chat_id: chat_id, text: text, disable_web_page_preview: true}
    |> maybe_put(:message_thread_id, opts[:message_thread_id])
    |> maybe_put(:reply_to_message_id, opts[:reply_to_message_id])
    |> maybe_put(:reply_markup, opts[:reply_markup])
    |> maybe_put(:parse_mode, opts[:parse_mode])
    |> then(&request("sendMessage", &1))
  end

  def send_chat_action(chat_id, opts \\ []) do
    %{chat_id: chat_id, action: "typing"}
    |> maybe_put(:message_thread_id, opts[:message_thread_id])
    |> then(&request("sendChatAction", &1))
  end

  def create_forum_topic(chat_id, name) do
    request("createForumTopic", %{chat_id: chat_id, name: name})
  end

  def answer_callback_query(callback_query_id, text \\ nil) do
    %{callback_query_id: callback_query_id}
    |> maybe_put(:text, text)
    |> then(&request("answerCallbackQuery", &1))
  end

  def edit_message_reply_markup(chat_id, message_id, reply_markup) do
    request("editMessageReplyMarkup", %{
      chat_id: chat_id,
      message_id: message_id,
      reply_markup: reply_markup
    })
  end

  # Private functions

  defp request(method, params, http_opts \\ []) do
    url = "#{@base_url}/bot#{token()}/#{method}"
    opts = Keyword.merge([timeout: 30_000, recv_timeout: 30_000], http_opts)

    HTTPoison.post(url, Jason.encode!(params), [{"Content-Type", "application/json"}], opts)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)["result"]}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.warning("[TelegramQABot] #{method} failed status=#{status_code} body=#{body}")
        {:error, {:http_error, status_code, body}}

      {:error, error} ->
        Logger.warning("[TelegramQABot] #{method} failed error=#{inspect(error)}")
        {:error, error}
    end
  end

  defp token(), do: System.get_env("TELEGRAM_QA_BOT_TOKEN")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
