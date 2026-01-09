defmodule Sanbase.AppNotifications.NotificationReadStatus do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.AppNotifications.Notification

  @primary_key {:id, :id, autogenerate: true}

  @type t :: %__MODULE__{
          id: pos_integer(),
          user_id: pos_integer(),
          notification_id: pos_integer(),
          read_at: DateTime.t()
        }

  schema "sanbase_notifications_read_status" do
    belongs_to(:user, User)
    belongs_to(:notification, Notification)

    field(:read_at, :utc_datetime)
  end

  @doc """
  Changeset for marking notifications as read per user.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(notification_user_read, attrs) do
    notification_user_read
    |> cast(attrs, [:user_id, :notification_id, :read_at])
    |> validate_required([:user_id, :notification_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:notification_id)
    |> unique_constraint([:user_id, :notification_id],
      name: :sanbase_notifications_read_status_user_id_notification_id_index
    )
  end
end
