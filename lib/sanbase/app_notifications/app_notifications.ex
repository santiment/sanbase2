defmodule Sanbase.AppNotifications do
  @moduledoc """
  Context for managing in-app notifications.
  """

  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.AppNotifications.{Notification, NotificationUserRead}

  @default_limit 20

  @doc """
  Creates a notification entry.
  """
  @spec create_notification(map()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def create_notification(attrs) when is_map(attrs) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the latest notifications that are visible to the provided user.

  By default returns the latest #{@default_limit} notifications.
  """
  @spec list_notifications_for_user(pos_integer(), keyword()) :: [Notification.t()]
  def list_notifications_for_user(user_id, opts \\ []) when is_integer(user_id) do
    limit = Keyword.get(opts, :limit, @default_limit)

    Notification
    |> accessible_notifications_query(user_id)
    |> join(:left, [n], nur in NotificationUserRead,
      on: nur.notification_id == n.id and nur.user_id == ^user_id
    )
    |> preload([n, _nur], [:user, :actor_user])
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> select_merge([_n, nur], %{read_at: nur.read_at})
    |> Repo.all()
  end

  @doc """
  Marks a notification as read for the given user.
  """
  @spec mark_notification_as_read(pos_integer(), pos_integer()) ::
          {:ok, NotificationUserRead.t()} | {:error, term()}
  def mark_notification_as_read(user_id, notification_id)
      when is_integer(user_id) and is_integer(notification_id) do
    with %Notification{} <- fetch_notification_for_user(user_id, notification_id),
         args = %{user_id: user_id, notification_id: notification_id, read_at: DateTime.utc_now()},
         changeset <- NotificationUserRead.changeset(%NotificationUserRead{}, args),
         {:ok, result} <- upsert_user_read(changeset) do
      {:ok, result}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp accessible_notifications_query(query, user_id) do
    from(n in query,
      where: n.is_deleted == false,
      where: n.user_id == ^user_id or n.is_broadcast
    )
  end

  defp fetch_notification_for_user(user_id, notification_id) do
    Notification
    |> accessible_notifications_query(user_id)
    |> where([n], n.id == ^notification_id)
    |> Repo.one()
  end

  defp upsert_user_read(changeset) do
    Repo.insert(changeset, on_conflict: :nothing)
  end
end
