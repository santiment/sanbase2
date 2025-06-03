defmodule Sanbase.Chat do
  @moduledoc """
  The Chat context module provides functions for managing chat conversations and messages.

  ## Features
  - Create new chat conversations with automatic title generation
  - Add user and assistant messages to chats
  - Retrieve chats and their messages
  - Context-aware messaging with dashboard, asset, and metrics information
  """

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Chat.{Chat, ChatMessage}

  @type chat_attrs :: %{
          title: String.t(),
          user_id: integer()
        }

  @type message_attrs :: %{
          content: String.t(),
          role: :user | :assistant,
          context: map()
        }

  @doc """
  Creates a new chat conversation with an initial user message.
  The chat title is derived from the first user message.
  """
  @spec create_chat_with_message(integer(), String.t(), map()) ::
          {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}
  def create_chat_with_message(user_id, content, context \\ %{}) do
    title = generate_title_from_content(content)

    Repo.transaction(fn ->
      with {:ok, chat} <- create_chat(%{title: title, user_id: user_id}),
           {:ok, _message} <- add_message_to_chat(chat.id, content, :user, context) do
        get_chat_with_messages!(chat.id)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Creates a new empty chat conversation.
  """
  @spec create_chat(chat_attrs()) :: {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}
  def create_chat(attrs) do
    attrs
    |> Chat.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Adds a message to an existing chat conversation.
  Also updates the chat's updated_at timestamp for proper ordering.
  """
  @spec add_message_to_chat(Ecto.UUID.t(), String.t(), :user | :assistant, map()) ::
          {:ok, ChatMessage.t()} | {:error, Ecto.Changeset.t()}
  def add_message_to_chat(chat_id, content, role, context \\ %{}) do
    Repo.transaction(fn ->
      # Insert the message
      message_result =
        %{
          chat_id: chat_id,
          content: content,
          role: role,
          context: context
        }
        |> ChatMessage.create_changeset()
        |> Repo.insert()

      case message_result do
        {:ok, message} ->
          # Update the chat's updated_at timestamp
          case get_chat(chat_id) do
            nil ->
              Repo.rollback({:error, :chat_not_found})

            chat ->
              case touch_chat_updated_at(chat) do
                {:ok, _} -> message
                {:error, changeset} -> Repo.rollback(changeset)
              end
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Adds an assistant response to a chat conversation.
  """
  @spec add_assistant_response(Ecto.UUID.t(), String.t(), map()) ::
          {:ok, ChatMessage.t()} | {:error, Ecto.Changeset.t()}
  def add_assistant_response(chat_id, content, context \\ %{}) do
    add_message_to_chat(chat_id, content, :assistant, context)
  end

  @doc """
  Retrieves a chat with all its messages, ordered by insertion time.
  """
  @spec get_chat_with_messages(Ecto.UUID.t()) :: Chat.t() | nil
  def get_chat_with_messages(chat_id) do
    Chat
    |> where([c], c.id == ^chat_id)
    |> preload([:user, :chat_messages])
    |> Repo.one()
  end

  @doc """
  Retrieves a chat with all its messages, raising if not found.
  """
  @spec get_chat_with_messages!(Ecto.UUID.t()) :: Chat.t()
  def get_chat_with_messages!(chat_id) do
    Chat
    |> where([c], c.id == ^chat_id)
    |> preload([:user, :chat_messages])
    |> Repo.one!()
  end

  @doc """
  Retrieves a chat by ID.
  """
  @spec get_chat(Ecto.UUID.t()) :: Chat.t() | nil
  def get_chat(chat_id) do
    Repo.get(Chat, chat_id)
  end

  @doc """
  Lists all chats for a specific user, ordered by most recent first.
  """
  @spec list_user_chats(integer()) :: [Chat.t()]
  def list_user_chats(user_id) do
    Chat
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists all chats for a specific user with their latest message preview.
  """
  @spec list_user_chats_with_preview(integer()) :: [Chat.t()]
  def list_user_chats_with_preview(user_id) do
    latest_message_query =
      from(cm in ChatMessage,
        select: %{chat_id: cm.chat_id, content: cm.content, inserted_at: cm.inserted_at},
        distinct: cm.chat_id,
        order_by: [cm.chat_id, desc: cm.inserted_at]
      )

    Chat
    |> where([c], c.user_id == ^user_id)
    |> join(:left, [c], lm in subquery(latest_message_query), on: c.id == lm.chat_id)
    |> select([c, lm], %{c | latest_message_content: lm.content})
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Deletes a chat and all its messages.
  """
  @spec delete_chat(Ecto.UUID.t()) :: {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}
  def delete_chat(chat_id) do
    chat_id
    |> get_chat()
    |> case do
      nil -> {:error, :not_found}
      chat -> Repo.delete(chat)
    end
  end

  @doc """
  Updates a chat's title.
  """
  @spec update_chat_title(Ecto.UUID.t(), String.t()) ::
          {:ok, Chat.t()} | {:error, Ecto.Changeset.t()}
  def update_chat_title(chat_id, new_title) do
    chat_id
    |> get_chat()
    |> case do
      nil ->
        {:error, :not_found}

      chat ->
        chat
        |> Chat.changeset(%{title: new_title})
        |> Repo.update()
    end
  end

  @doc """
  Gets messages for a specific chat, with optional pagination.
  """
  @spec get_chat_messages(Ecto.UUID.t(), keyword()) :: [ChatMessage.t()]
  def get_chat_messages(chat_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    ChatMessage
    |> where([cm], cm.chat_id == ^chat_id)
    |> order_by([cm], asc: cm.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp generate_title_from_content(content) do
    content
    |> String.trim()
    |> String.slice(0, 50)
    |> case do
      trimmed when byte_size(trimmed) == 50 -> trimmed <> "..."
      trimmed -> trimmed
    end
  end

  defp touch_chat_updated_at(chat) do
    chat
    |> Chat.changeset(%{})
    |> Ecto.Changeset.put_change(
      :updated_at,
      NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update()
  end
end
