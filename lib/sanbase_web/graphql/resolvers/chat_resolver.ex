defmodule SanbaseWeb.Graphql.Resolvers.ChatResolver do
  @moduledoc """
  GraphQL resolvers for Chat queries and mutations
  """

  import Absinthe.Resolution.Helpers, warn: false

  alias Sanbase.Chat

  @doc "Get current user's chats ordered by most recent activity"
  def my_chats(_root, _args, %{context: %{auth: %{current_user: current_user}}}) do
    chats = Chat.list_user_chats(current_user.id)

    chat_summaries =
      Enum.map(chats, fn chat ->
        messages = Chat.get_chat_messages(chat.id, limit: 1)
        latest_message = List.first(messages)

        %{
          id: chat.id,
          title: chat.title,
          inserted_at: chat.inserted_at,
          updated_at: chat.updated_at,
          messages_count: length(Chat.get_chat_messages(chat.id)),
          latest_message: latest_message
        }
      end)

    {:ok, chat_summaries}
  end

  @doc "Get a specific chat by ID with all messages"
  def get_chat(_root, %{id: chat_id}, %{context: %{auth: %{current_user: current_user}}}) do
    case Chat.get_chat_with_messages(chat_id) do
      nil ->
        {:error, "Chat not found"}

      chat ->
        if chat.user_id == current_user.id do
          {:ok, chat}
        else
          {:error, "Access denied"}
        end
    end
  end

  @doc "Get messages for a specific chat with pagination"
  def get_chat_messages(_root, %{chat_id: chat_id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case Chat.get_chat(chat_id) do
      nil ->
        {:error, "Chat not found"}

      chat ->
        if chat.user_id == current_user.id do
          limit = Map.get(args, :limit, 50)
          offset = Map.get(args, :offset, 0)
          messages = Chat.get_chat_messages(chat_id, limit: limit, offset: offset)
          {:ok, messages}
        else
          {:error, "Access denied"}
        end
    end
  end

  @doc "Send a user message - creates new chat if chatId not provided, adds to existing chat otherwise"
  def send_chat_message(_root, %{input: input}, %{context: %{auth: %{current_user: current_user}}}) do
    context = parse_context_input(Map.get(input, :context, %{}))

    case Map.get(input, :chat_id) do
      nil ->
        # Create new chat with the user message
        case Chat.create_chat_with_message(current_user.id, input.content, context) do
          {:ok, chat} -> {:ok, chat}
          {:error, changeset} -> {:error, format_changeset_errors(changeset)}
        end

      chat_id ->
        # Add user message to existing chat
        case Chat.get_chat(chat_id) do
          nil ->
            {:error, "Chat not found"}

          chat ->
            if chat.user_id == current_user.id do
              case Chat.add_message_to_chat(chat_id, input.content, :user, context) do
                {:ok, _message} ->
                  # Return the updated chat with messages
                  {:ok, Chat.get_chat_with_messages(chat_id)}

                {:error, changeset} ->
                  {:error, format_changeset_errors(changeset)}
              end
            else
              {:error, "Access denied"}
            end
        end
    end
  end

  @doc "Delete a chat"
  def delete_chat(_root, %{id: chat_id}, %{context: %{auth: %{current_user: current_user}}}) do
    case Chat.get_chat(chat_id) do
      nil ->
        {:error, "Chat not found"}

      chat ->
        if chat.user_id == current_user.id do
          case Chat.delete_chat(chat_id) do
            {:ok, deleted_chat} -> {:ok, deleted_chat}
            {:error, :not_found} -> {:error, "Chat not found"}
            {:error, changeset} -> {:error, format_changeset_errors(changeset)}
          end
        else
          {:error, "Access denied"}
        end
    end
  end

  # Field resolvers for nested fields
  def chat_messages(%{id: chat_id}, _args, _resolution) do
    messages = Chat.get_chat_messages(chat_id)
    {:ok, messages}
  end

  def messages_count(%{id: chat_id}, _args, _resolution) do
    count = Chat.get_chat_messages(chat_id) |> length()
    {:ok, count}
  end

  def latest_message(%{id: chat_id}, _args, _resolution) do
    case Chat.get_chat_messages(chat_id, limit: 1) do
      [message | _] -> {:ok, message}
      [] -> {:ok, nil}
    end
  end

  # Helper functions
  defp parse_context_input(nil), do: %{}

  defp parse_context_input(%{} = context) do
    context
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      string_key = to_string(key)
      Map.put(acc, string_key, value)
    end)
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
