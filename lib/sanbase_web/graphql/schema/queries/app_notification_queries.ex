defmodule SanbaseWeb.Graphql.Schema.AppNotificationQueries do
  @moduledoc """
  Queries and mutations for working with App Notifications
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.AppNotificationResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :app_notification_queries do
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
  end
end
