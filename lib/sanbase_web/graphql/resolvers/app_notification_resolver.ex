defmodule SanbaseWeb.Graphql.Resolvers.AppNotificationResolver do
  alias Sanbase.AppNotifications

  @doc """
  Fetch notifications for the current user with cursor-based pagination.
  """
  def get_notifications(_root, args, %{context: %{auth: %{current_user: user}}}) do
    opts = build_opts(args)

    with {:ok, paginated} <-
           user.id
           |> AppNotifications.list_notifications_for_user(opts)
           |> AppNotifications.wrap_with_cursor() do
      available_types = AppNotifications.list_available_notification_types_for_user(user.id)
      stats = AppNotifications.get_notifications_stats(user.id, opts)

      {:ok,
       paginated
       |> Map.put(:available_notification_types, available_types)
       |> Map.put(:stats, stats)}
    end
  end

  @doc """
  Set the read status of a notification.
  """
  def set_read_status(_root, %{notification_id: notification_id, is_read: is_read}, %{
        context: %{auth: %{current_user: user}}
      }) do
    case AppNotifications.set_read_status(user.id, notification_id, is_read) do
      {:ok, _} -> AppNotifications.get_notification_for_user(user.id, notification_id)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolver for the is_read virtual field.
  Returns true if the notification has a read_at timestamp.
  """
  def is_read(%{read_at: read_at}, _args, _resolution) do
    {:ok, not is_nil(read_at)}
  end

  defp build_opts(args) do
    opts = [limit: Map.get(args, :limit, 20)]

    opts =
      case Map.get(args, :cursor) do
        nil -> opts
        cursor -> Keyword.put(opts, :cursor, cursor)
      end

    case Map.get(args, :types) do
      nil -> opts
      [] -> opts
      types -> Keyword.put(opts, :types, types)
    end
  end
end
