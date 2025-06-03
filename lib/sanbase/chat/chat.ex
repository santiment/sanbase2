defmodule Sanbase.Chat.Chat do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Chat.ChatMessage

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t(),
          user_id: integer(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          chat_messages: [ChatMessage.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chats" do
    field(:title, :string)
    belongs_to(:user, User, type: :integer)
    has_many(:chat_messages, ChatMessage, preload_order: [asc: :inserted_at])

    timestamps()
  end

  @required_fields [:title, :user_id]
  @optional_fields []

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = chat, attrs \\ %{}) do
    chat
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: 255)
    |> foreign_key_constraint(:user_id)
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end
end
