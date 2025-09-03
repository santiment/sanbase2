defmodule SanbaseWeb.Graphql.Schema.ChatQueries do
  @moduledoc """
  Queries and mutations for working with Chats and Chat Messages
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ChatResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :chat_queries do
    @desc "Get current user's chats ordered by most recent activity"
    field :my_chats, list_of(:chat_summary) do
      meta(access: :free)

      middleware(JWTAuth)
      resolve(&ChatResolver.my_chats/3)
    end

    @desc "Get a specific chat by ID with all messages"
    field :chat, :chat do
      meta(access: :free)

      arg(:id, non_null(:id))

      resolve(&ChatResolver.get_chat/3)
    end

    @desc "Get messages for a specific chat with pagination"
    field :chat_messages, list_of(:chat_message) do
      meta(access: :free)

      arg(:chat_id, non_null(:id))
      arg(:limit, :integer, default_value: 50)
      arg(:offset, :integer, default_value: 0)

      resolve(&ChatResolver.get_chat_messages/3)
    end

    @desc "Get Academy Q&A question suggestions based on a search query"
    field :academy_autocomplete_questions, list_of(:academy_question_suggestion) do
      meta(access: :free)

      arg(:query, non_null(:string))

      resolve(&ChatResolver.academy_autocomplete_questions/3)
    end
  end

  object :chat_mutations do
    @desc """
    Send a user message to a chat. If chatId is not provided, creates a new chat.
    If chatId is provided, adds the user message to the existing chat.
    All messages sent through this API are user messages.
    """
    field :send_chat_message, :chat do
      arg(:chat_id, :id)
      arg(:content, non_null(:string))
      arg(:context, :chat_context_input)
      arg(:type, :chat_type, default_value: :dyor_dashboard)

      resolve(&ChatResolver.send_chat_message/3)
    end

    @desc "Delete a chat and all its messages"
    field :delete_chat, :chat do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&ChatResolver.delete_chat/3)
    end

    @desc """
    Submit feedback for a chat message. Implements toggle behavior:
    - Same feedback type removes feedback (sets to null)
    - Different feedback type switches to the new type
    - Only works on assistant messages
    """
    field :submit_chat_message_feedback, :chat_message do
      arg(:message_id, non_null(:id))
      arg(:feedback_type, non_null(:chat_message_feedback_type))

      resolve(&ChatResolver.submit_message_feedback/3)
    end
  end
end
