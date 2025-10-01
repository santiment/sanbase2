defmodule SanbaseWeb.Graphql.Resolvers.ChatResolver do
  @moduledoc """
  GraphQL resolvers for Chat queries and mutations
  """

  import Absinthe.Resolution.Helpers, warn: false

  alias Sanbase.Chat
  alias Sanbase.AI.ChatAIService
  alias Sanbase.AI.AcademyAIService

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
          type: chat.type,
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
        if can_access_chat?(chat, current_user) do
          {:ok, chat}
        else
          {:error, "Access denied"}
        end
    end
  end

  def get_chat(_root, %{id: chat_id}, _context) do
    case Chat.get_chat_with_messages(chat_id) do
      nil ->
        {:error, "Chat not found"}

      chat ->
        if can_access_chat?(chat, nil) do
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
        if can_access_chat?(chat, current_user) do
          limit = Map.get(args, :limit, 50)
          offset = Map.get(args, :offset, 0)
          messages = Chat.get_chat_messages(chat_id, limit: limit, offset: offset)
          {:ok, messages}
        else
          {:error, "Access denied"}
        end
    end
  end

  def get_chat_messages(_root, %{chat_id: chat_id} = args, _context) do
    case Chat.get_chat(chat_id) do
      nil ->
        {:error, "Chat not found"}

      chat ->
        if can_access_chat?(chat, nil) do
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
  def send_chat_message(_root, args, %{context: %{auth: %{current_user: current_user}}}) do
    context = parse_context_input(Map.get(args, :context, %{}))
    chat_type = convert_enum_to_string(Map.get(args, :type, :dyor_dashboard))

    result =
      case Map.get(args, :chat_id) do
        nil ->
          # Create new chat with the user message
          case Chat.create_chat_with_message(current_user.id, args.content, context, chat_type) do
            {:ok, chat} ->
              # Get the initial user message ID (first message in a new chat)
              user_message = List.first(chat.chat_messages)

              # For new chats, generate AI title and response synchronously
              maybe_generate_ai_response(chat, args.content, context, current_user.id,
                is_new_chat: true,
                message_id: user_message.id
              )

              # Return the updated chat with AI response
              {:ok, Chat.get_chat_with_messages(chat.id)}

            {:error, changeset} ->
              {:error, format_changeset_errors(changeset)}
          end

        chat_id ->
          # Add user message to existing chat
          case Chat.get_chat(chat_id) do
            nil ->
              {:error, "Chat not found"}

            chat ->
              if chat.user_id == current_user.id do
                case Chat.add_message_to_chat(chat_id, args.content, :user, context) do
                  {:ok, message} ->
                    # Generate AI response for existing chat synchronously
                    maybe_generate_ai_response(chat, args.content, context, current_user.id,
                      is_new_chat: false,
                      message_id: message.id
                    )

                    # Return the updated chat with AI response
                    {:ok, Chat.get_chat_with_messages(chat_id)}

                  {:error, changeset} ->
                    {:error, format_changeset_errors(changeset)}
                end
              else
                {:error, "Access denied"}
              end
          end
      end

    result
  end

  def send_chat_message(_root, args, _context) do
    context = parse_context_input(Map.get(args, :context, %{}))
    chat_type = convert_enum_to_string(Map.get(args, :type, :dyor_dashboard))

    result =
      case Map.get(args, :chat_id) do
        nil ->
          # Create new anonymous chat with the user message
          case Chat.create_chat_with_message(nil, args.content, context, chat_type) do
            {:ok, chat} ->
              # Get the initial user message ID (first message in a new chat)
              user_message = List.first(chat.chat_messages)

              # For new chats, generate AI response synchronously (no title generation for anonymous)
              maybe_generate_ai_response(chat, args.content, context, nil,
                is_new_chat: true,
                message_id: user_message.id
              )

              # Return the updated chat with AI response
              {:ok, Chat.get_chat_with_messages(chat.id)}

            {:error, changeset} ->
              {:error, format_changeset_errors(changeset)}
          end

        chat_id ->
          # Add user message to existing anonymous chat
          case Chat.get_chat(chat_id) do
            nil ->
              {:error, "Chat not found"}

            chat ->
              if can_access_chat?(chat, nil) do
                case Chat.add_message_to_chat(chat_id, args.content, :user, context) do
                  {:ok, message} ->
                    # Generate AI response for existing chat synchronously
                    maybe_generate_ai_response(chat, args.content, context, nil,
                      is_new_chat: false,
                      message_id: message.id
                    )

                    # Return the updated chat with AI response
                    {:ok, Chat.get_chat_with_messages(chat_id)}

                  {:error, changeset} ->
                    {:error, format_changeset_errors(changeset)}
                end
              else
                {:error, "Access denied"}
              end
          end
      end

    result
  end

  @doc "Delete a chat"
  def delete_chat(_root, %{id: chat_id}, %{context: %{auth: %{current_user: current_user}}}) do
    case Chat.get_chat(chat_id) do
      nil ->
        {:error, "Chat not found"}

      chat ->
        if can_access_chat?(chat, current_user) do
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

  @doc "Submit feedback for a chat message"
  def submit_message_feedback(
        _root,
        %{message_id: message_id, feedback_type: feedback_type},
        _context
      ) do
    # Convert GraphQL enum to string
    feedback_string = convert_feedback_enum_to_string(feedback_type)

    case Chat.update_message_feedback(message_id, feedback_string) do
      {:ok, updated_message} ->
        {:ok, updated_message}

      {:error, :message_not_found} ->
        {:error, "Message not found"}

      {:error, changeset} ->
        {:error, format_changeset_errors(changeset)}
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

  @doc "Get Academy Q&A question suggestions based on a search query"
  def academy_autocomplete_questions(_root, %{query: query}, _context) do
    case AcademyAIService.autocomplete_questions(query) do
      {:ok, suggestions} ->
        # Transform the string-keyed maps to atom-keyed maps for GraphQL
        transformed_suggestions =
          Enum.map(suggestions, fn suggestion ->
            %{
              title: Map.get(suggestion, "title"),
              question: Map.get(suggestion, "question")
            }
          end)

        {:ok, transformed_suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions
  defp convert_enum_to_string(:dyor_dashboard), do: "dyor_dashboard"
  defp convert_enum_to_string(:academy_qa), do: "academy_qa"
  defp convert_enum_to_string(type) when is_binary(type), do: type

  defp convert_feedback_enum_to_string(:thumbs_up), do: "thumbs_up"
  defp convert_feedback_enum_to_string(:thumbs_down), do: "thumbs_down"

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

  defp maybe_generate_ai_response(chat, user_message, context, user_id, opts) do
    # Generate AI responses based on chat type
    case chat.type do
      "dyor_dashboard" ->
        # Generate DYOR AI response synchronously
        case ChatAIService.generate_ai_response(user_message, context, chat.id, user_id) do
          {:ok, ai_response} ->
            Chat.add_assistant_response(chat.id, ai_response)

          {:error, reason} ->
            require Logger
            Logger.error("Failed to generate AI response: #{reason}")
        end

        # Generate chat title for new chats synchronously (only for authenticated users)
        if Keyword.get(opts, :is_new_chat, false) && user_id do
          case ChatAIService.generate_and_update_chat_title_sync(chat.id, user_message) do
            {:ok, _updated_chat} ->
              :ok

            {:error, reason} ->
              require Logger
              Logger.error("Failed to update chat title: #{inspect(reason)}")
          end
        end

      "academy_qa" ->
        case AcademyAIService.generate_local_response(user_message, chat.id, user_id, true) do
          {:ok, %{answer: answer, sources: sources, suggestions: suggestions}} ->
            Chat.add_assistant_response_with_sources_and_suggestions(
              chat.id,
              answer,
              sources,
              suggestions
            )

          {:error, reason} ->
            require Logger
            Logger.error("Failed to generate Academy AI response: #{reason}")
        end

        # Generate chat title for new chats synchronously (only for authenticated users)
        if Keyword.get(opts, :is_new_chat, false) && user_id do
          case ChatAIService.generate_and_update_chat_title_sync(chat.id, user_message) do
            {:ok, _updated_chat} ->
              :ok

            {:error, reason} ->
              require Logger
              Logger.error("Failed to update chat title: #{inspect(reason)}")
          end
        end

      _ ->
        # No AI response for unknown chat types
        :ok
    end

    :ok
  end

  # Access control helper
  defp can_access_chat?(chat, current_user) do
    cond do
      # Authenticated user owns the chat
      current_user && chat.user_id == current_user.id -> true
      # Anonymous chat (no owner) - anyone can access
      is_nil(chat.user_id) -> true
      # No access
      true -> false
    end
  end
end
