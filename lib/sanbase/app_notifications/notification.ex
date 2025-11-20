defmodule Sanbase.AppNotifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.AppNotifications.NotificationUserRead

  @required_fields [:type]

  @optional_fields [
    :title,
    :content,
    :user_id,
    :actor_user_id,
    :entity_type,
    :entity_id,
    :is_system_generated,
    :is_broadcast,
    :grouping_key,
    :json_data,
    :is_deleted
  ]

  @typedoc """
  Schema for an app-level notification persisted in `sanbase_notifications`.
  """
  @type t :: %__MODULE__{
          id: pos_integer(),
          type: String.t(),
          title: String.t(),
          content: String.t() | nil,
          user_id: pos_integer() | nil,
          actor_user_id: pos_integer() | nil,
          entity_type: String.t() | nil,
          entity_id: integer() | nil,
          is_system_generated: boolean(),
          is_broadcast: boolean(),
          grouping_key: String.t() | nil,
          json_data: map() | nil,
          is_deleted: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "sanbase_notifications" do
    field(:type, :string)
    field(:title, :string)
    field(:content, :string)

    field(:entity_type, :string)
    field(:entity_id, :integer)

    field(:is_system_generated, :boolean, default: false)
    field(:is_broadcast, :boolean, default: false)
    field(:grouping_key, :string)

    field(:json_data, :map)
    field(:is_deleted, :boolean, default: false)

    # Virtual field populated when we join the user reads
    field(:read_at, :utc_datetime, virtual: true)

    belongs_to(:user, User)
    belongs_to(:actor_user, User)

    has_many(:user_reads, NotificationUserRead)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Build a changeset for creating or updating notifications.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:actor_user_id)
  end
end
