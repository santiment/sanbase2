defmodule Sanbase.Chat.Chat do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Chat.ChatMessage

  @chat_types ["dyor_dashboard", "academy_qa"]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          type: String.t(),
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          chat_messages: [ChatMessage.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chats" do
    field(:title, :string)
    field(:type, :string, default: "dyor_dashboard")
    belongs_to(:user, User, type: :integer)
    has_many(:chat_messages, ChatMessage, preload_order: [asc: :inserted_at])

    timestamps()
  end

  @required_fields [:title]
  @optional_fields [:type, :user_id]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = chat, attrs \\ %{}) do
    chat
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_inclusion(:type, @chat_types,
      message: "must be one of: #{Enum.join(@chat_types, ", ")}"
    )
    |> validate_user_id()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_user_id(changeset) do
    case get_change(changeset, :user_id) do
      # Allow nil for anonymous chats
      nil -> changeset
      user_id when is_integer(user_id) and user_id > 0 -> changeset
      _ -> add_error(changeset, :user_id, "must be a positive integer or nil for anonymous chats")
    end
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  @spec chat_types() :: [String.t()]
  def chat_types, do: @chat_types
end
