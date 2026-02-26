defmodule SanbaseWeb.Graphql.Schema.AppNotificationQueries do
  @moduledoc """
  Queries and mutations for working with App Notifications
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.AppNotificationResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :app_notification_queries do
    @desc """
    Returns the list of users whose notifications the current user has muted.
    """
    field :get_notification_muted_users, list_of(:public_user) do
      meta(access: :free)

      middleware(JWTAuth)
      resolve(&AppNotificationResolver.list_muted_users/3)
    end

    @desc """
    Fetch notifications for the current logged-in user.
    Supports cursor-based pagination for infinite scrolling.

    The cursor parameter accepts:
    - type: BEFORE or AFTER
    - datetime: The datetime to paginate from

    For infinite scrolling, use BEFORE cursor type with the datetime
    from the last notification in the previous page.
    """
    field :get_current_user_notifications, :app_notifications_paginated do
      meta(access: :free)

      arg(:limit, :integer, default_value: 20)
      arg(:cursor, :cursor_input)
      arg(:types, list_of(:string))

      middleware(JWTAuth)
      resolve(&AppNotificationResolver.get_notifications/3)
    end
  end

  object :app_notification_mutations do
    @desc """
    Set the read status of a notification for the current user.
    Pass isRead: true to mark as read, isRead: false to mark as unread.
    """
    field :set_notification_read_status, :app_notification do
      arg(:notification_id, non_null(:integer))
      arg(:is_read, non_null(:boolean))

      middleware(JWTAuth)
      resolve(&AppNotificationResolver.set_read_status/3)
    end

    @desc """
    Mark all unread notifications as read for the current user.
    Returns the number of notifications that were marked as read.
    """
    field :mark_all_notifications_as_read, :mark_all_notifications_as_read_result do
      middleware(JWTAuth)
      resolve(&AppNotificationResolver.mark_all_as_read/3)
    end

    @desc """
    Mute notifications from a specific user. Future notifications triggered
    by the muted user's actions will be silently dropped.
    """
    field :mute_user_notifications, :public_user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&AppNotificationResolver.mute_user/3)
    end

    @desc """
    Unmute a previously muted user to resume receiving their notifications.
    """
    field :unmute_user_notifications, :public_user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&AppNotificationResolver.unmute_user/3)
    end
  end
end
