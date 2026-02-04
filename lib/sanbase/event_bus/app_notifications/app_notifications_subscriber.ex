defmodule Sanbase.EventBus.AppNotificationsSubscriber do
  @moduledoc """
  Create Sanbase App Notifications based on various events in the system.

  To create a notification from an event, write a handle_event/3 function clause
  that matches the event type you want to create a notification from.
  From the handle_event/3 function you can call the create_notification/3 function,
  passing the notification type, the list of user ids that should receive the notification
  and the event data itself.

  The create_notification/3 function should follow the convention that it:
  - creates the Notification record for this notification
  - creates an anonymous function that takes a user_id and returns a NotificationReadStatus struct
  - calls the multi_insert_notifications/2 function, passing the list of user ids and the anonymous function
    which will create the NotificationUserRead struct for each user.


  """
  use GenServer

  alias Sanbase.AppNotifications
  alias Sanbase.AppNotifications.NotificationReadStatus

  require Logger

  def topics(), do: [".*"]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def init(opts) do
    {:ok, opts}
  end

  def process({_topic, _id} = event_shadow) do
    GenServer.cast(__MODULE__, event_shadow)
    :ok
  end

  def handle_cast({_topic, _id} = event_shadow, state) do
    event = EventBus.fetch_event(event_shadow)

    new_state =
      Sanbase.EventBus.handle_event(
        __MODULE__,
        event,
        event_shadow,
        state,
        fn -> handle_event(event, event_shadow, state) end
      )

    {:noreply, new_state}
  end

  # Needed to handle the async tasks
  def handle_info({ref, :ok}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    Logger.error(
      "AppNotificationsSubscriber notification task failed with reason: #{inspect(reason)}"
    )

    {:noreply, state}
  end

  defp handle_event(
         %{
           data: %{event_type: :publish_insight, user_id: user_id} = data
         },
         event_shadow,
         state
       ) do
    create_notification(:publish_insight, followers_user_ids(user_id), data)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: event_type, user_id: user_id} = data},
         event_shadow,
         state
       )
       when event_type in [:create_watchlist, :update_watchlist] do
    create_notification(event_type, followers_user_ids(user_id), data)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{
           data: %{event_type: :create_comment, entity_owner_user_id: entity_owner_user_id} = data
         },
         event_shadow,
         state
       )
       when is_integer(entity_owner_user_id) do
    # Do not notify the author of a comment when they comment on their own entity
    if not same_author_and_receiver?(:create_comment, data) do
      create_notification(:create_comment, [entity_owner_user_id], data)
    end

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{
           data: %{event_type: :create_vote, entity_owner_user_id: entity_owner_user_id} = data
         },
         event_shadow,
         state
       )
       when is_integer(entity_owner_user_id) do
    # Do not notify the author of a comment when they vote on their own entity
    # or when the same voter votes many times in a short period of time
    if not in_cooldown_period?(:create_vote, data) and
         not same_author_and_receiver?(:create_vote, data) do
      create_notification(:create_vote, [entity_owner_user_id], data)
    end

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{
           data:
             %{event_type: :alert_triggered, user_id: user_id, alert_id: alert_id, alert_title: _} =
               data
         },
         event_shadow,
         state
       )
       when is_integer(user_id) and is_integer(alert_id) do
    create_notification(:alert_triggered, [user_id], data)

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp followers_user_ids(user_id) do
    Sanbase.Accounts.UserFollower.followers_of(user_id)
    |> Enum.map(& &1.id)
  end

  defp create_notification(_type, [] = _user_ids, _data) do
    # No recepients, so no notifications
    :ok
  end

  defp create_notification(_type, _user_ids, %{is_public: false}) do
    # No notifications for private entities
    :ok
  end

  ## Insight notifications

  defp create_notification(:publish_insight, user_ids, %{
         insight_id: insight_id,
         title: title,
         user_id: author_id
       }) do
    {:ok, notification} =
      AppNotifications.create_notification(%{
        type: "publish_insight",
        user_id: author_id,
        entity_type: "insight",
        entity_name: title,
        entity_id: insight_id,
        is_broadcast: false,
        is_system_generated: false
      })

    multi_insert_notification_read_status(user_ids, notification.id)
  end

  ## Watchlist notifications
  defp create_notification(:create_watchlist, user_ids, %{
         # Only public watchlists generate notifications
         is_public: true,
         watchlist_id: watchlist_id,
         name: name,
         user_id: author_id
       }) do
    {:ok, notification} =
      AppNotifications.create_notification(%{
        type: "create_watchlist",
        user_id: author_id,
        entity_type: "watchlist",
        entity_id: watchlist_id,
        entity_name: name,
        is_broadcast: false,
        is_system_generated: false
      })

    multi_insert_notification_read_status(user_ids, notification.id)
  end

  defp create_notification(
         :update_watchlist,
         user_ids,
         %{
           is_public: true,
           watchlist_id: watchlist_id,
           name: name,
           user_id: author_id,
           extra_in_memory_data: %{changes: changes}
         }
       ) do
    changed_fields = update_watchlist_changed_fields(changes)

    if changed_fields != [] do
      json_data =
        update_watchlist_list_additional_json_data(changes)
        |> Map.merge(%{changed_fields: changed_fields})

      {:ok, notification} =
        AppNotifications.create_notification(%{
          type: "update_watchlist",
          user_id: author_id,
          entity_type: "watchlist",
          entity_name: name,
          entity_id: watchlist_id,
          is_broadcast: false,
          is_system_generated: false,
          json_data: json_data
        })

      multi_insert_notification_read_status(user_ids, notification.id)
    end
  end

  defp create_notification(
         :create_comment,
         user_ids,
         %{
           comment_id: comment_id,
           entity_type: entity_type,
           entity_id: entity_id,
           entity_name: entity_name,
           user_id: author_id
         }
       ) do
    with %Sanbase.Comment{content: content} <- Sanbase.Comment.by_id(comment_id) do
      comment_preview = String.slice(content, 0, 150)

      {:ok, notification} =
        AppNotifications.create_notification(%{
          type: "create_comment",
          user_id: author_id,
          # A comment can be attached to an entity of any type - watchlist, insight, chart, etc.
          entity_type: to_string(entity_type),
          entity_name: entity_name,
          entity_id: entity_id,
          is_broadcast: false,
          is_system_generated: false,
          json_data: %{"comment_preview" => comment_preview}
        })

      # There's one receiver - the owner of the entity - but we can reuse
      # the multi_insert_notification_read_status function to insert the notification read status
      multi_insert_notification_read_status(user_ids, notification.id)
    end
  end

  defp create_notification(
         :create_vote,
         user_ids,
         %{
           entity_type: entity_type,
           entity_id: entity_id,
           entity_name: entity_name,
           user_id: author_id
         }
       ) do
    {:ok, notification} =
      AppNotifications.create_notification(%{
        type: "create_vote",
        user_id: author_id,
        entity_type: to_string(entity_type),
        entity_name: entity_name,
        entity_id: entity_id,
        is_broadcast: false,
        is_system_generated: false,
        json_data: %{}
      })

    multi_insert_notification_read_status(user_ids, notification.id)
  end

  defp create_notification(
         :alert_triggered,
         user_ids,
         %{
           user_id: user_id,
           alert_id: alert_id,
           alert_title: alert_title
         }
       ) do
    {:ok, notification} =
      AppNotifications.create_notification(%{
        type: "alert_triggered",
        user_id: user_id,
        entity_type: "user_trigger",
        entity_name: alert_title || "Alert #{alert_id}",
        entity_id: alert_id,
        is_broadcast: false,
        is_system_generated: false,
        json_data: %{}
      })

    multi_insert_notification_read_status(user_ids, notification.id)
  end

  defp multi_insert_notification_read_status(user_ids, notification_id) do
    user_ids
    |> Enum.reduce(Ecto.Multi.new(), fn user_id, multi ->
      Ecto.Multi.insert(
        multi,
        {:notification, user_id, notification_id},
        AppNotifications.notification_read_status_changeset(%{
          notification_id: notification_id,
          user_id: user_id,
          read_at: nil
        })
      )
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, result} ->
        async_broadcast_websocket_notifications(result)

        {:ok, result}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp async_broadcast_websocket_notifications(result) do
    result
    |> Enum.map(fn {_key, %NotificationReadStatus{} = nrs} -> nrs end)
    |> AppNotifications.async_broadcast_websocket_notifications()
  end

  defp update_watchlist_changed_fields(changes) do
    changed_fields = if changes[:is_public], do: [:is_public], else: []
    changed_fields = if changes[:function], do: [:function | changed_fields], else: changed_fields

    changed_fields =
      if changes[:list_items], do: [:list_items | changed_fields], else: changed_fields

    # If the public status was changed private -> public, but the watchlist has been made public
    # not that long ago, do not notify about it. An example is someone clicking the public/private toggle
    # multiple times in a short period - this should not spam followers with notifications.
    old_dt = changes[:old_is_public_updated_at]

    if old_dt && changes[:is_public] && DateTime.diff(DateTime.utc_now(), old_dt, :day) < 2,
      do: changed_fields -- [:is_public],
      else: changed_fields
  end

  defp update_watchlist_list_additional_json_data(changes) do
    # If list_items have been added/removed, include the count in the json_data
    if is_integer(changes[:affected_list_items_count]) and
         changes[:affected_list_items_count] > 0,
       do: %{
         changes: [
           %{
             field: :list_items,
             change_type: changes[:list_items],
             changes_count: changes[:affected_list_items_count]
           }
         ]
       },
       else: %{}
  end

  defp in_cooldown_period?(:create_vote, %{
         entity_type: entity_type,
         entity_id: entity_id,
         user_id: voter_id
       }) do
    case AppNotifications.last_notification_created_by(
           :create_vote,
           entity_type,
           entity_id,
           voter_id
         ) do
      {:ok, notification} ->
        minutes_diff = DateTime.diff(DateTime.utc_now(), notification.inserted_at, :minute)
        abs(minutes_diff) <= 5

      _ ->
        false
    end
  end

  defp in_cooldown_period?(_type, _data), do: false

  defp same_author_and_receiver?(:create_vote, %{
         user_id: voter_id,
         entity_owner_user_id: entity_owner_user_id
       }) do
    voter_id == entity_owner_user_id
  end

  defp same_author_and_receiver?(:create_comment, %{
         user_id: voter_id,
         entity_owner_user_id: entity_owner_user_id
       }) do
    voter_id == entity_owner_user_id
  end

  defp same_author_and_receiver?(_type, _data) do
    false
  end
end
