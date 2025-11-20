defmodule Sanbase.EventBus.AppNotificationsSubscriber do
  @moduledoc """
  """
  use GenServer

  alias Sanbase.Utils.Config

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
    Logger.error("Metric registry notification task failed with reason: #{inspect(reason)}")
    {:noreply, state}
  end

  defp handle_event(
         %{
           data: %{event_type: :publish_insight, user_id: user_id, insight_id: insight_id} = data
         },
         event_shadow,
         state
       ) do
    create_notification(
      :publish_insight,
      followers_user_ids(user_id),
      data
    )

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(
         %{data: %{event_type: event_type, user_id: user_id} = data},
         event_shadow,
         state
       )
       when event_type in [:create_watchlist, :update_watchlist] do
    create_notification(
      event_type,
      followers_user_ids(user_id),
      data
    )

    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  defp handle_event(_event, event_shadow, state) do
    EventBus.mark_as_completed({__MODULE__, event_shadow})
    state
  end

  #
  defp followers_user_ids(user_id) do
    [user_id] ++ Sanbase.Accounts.UserFollower.followed_by_user_ids(user_id)
  end

  ## Insight notifications

  defp create_notification(_type, _user_ids, %{is_public: false}) do
    # No notifications for private insights
    :ok
  end

  defp create_notification(:publish_insight, user_ids, %{
         insight_id: insight_id,
         user_id: author_id
       }) do
    user_id_to_notification_fun = fn user_id ->
      %Sanbase.AppNotifications.Notification{
        type: "publish_insight",
        user_id: user_id,
        actor_user_id: author_id,
        entity_type: "insight",
        entity_id: insight_id,
        is_broadcast: false,
        is_system_generated: false
      }
    end

    multi_insert_notifications(user_ids, user_id_to_notification_fun)
  end

  ## Watchlist notifications
  defp create_notification(:create_watchlist, user_ids, %{
         # Only public watchlists generate notifications
         is_public: true,
         watchlist_id: watchlist_id,
         user_id: author_id
       }) do
    user_id_to_notification_fun = fn user_id ->
      %Sanbase.AppNotifications.Notification{
        type: "create_watchlist",
        user_id: user_id,
        actor_user_id: author_id,
        entity_type: "watchlist",
        entity_id: watchlist_id,
        is_broadcast: false,
        is_system_generated: false
      }
    end

    multi_insert_notifications(user_ids, user_id_to_notification_fun)
  end

  defp create_notification(
         :update_watchlist,
         user_ids,
         %{
           is_public: true,
           watchlist_id: watchlist_id,
           user_id: author_id,
           extra_in_memory_data: %{changes: changes}
         } =
           params
       ) do
    changed_fields = if changes[:is_public], do: [:is_public], else: []
    changed_fields = if changes[:function], do: [:function | changed_fields], else: changed_fields

    changed_fields =
      if changes[:list_items], do: [:list_items | changed_fields], else: changed_fields

    # If the public status was changed private -> public, but the watchlist has been made public
    # not that long ago, do not notify about it. An example is someone clicking the public/private toggle
    # multiple times in a short period - this should not spam followers with notifications.
    old_dt = changes[:old_is_public_updated_at]

    changed_fields =
      if old_dt && changes[:is_public] && DateTime.diff(DateTime.utc_now(), old_dt, :day) < 2,
        do: changed_fields -- [:is_public],
        else: changed_fields

    # If list_items have been added/removed, include the count in the json_data
    additional_json_data =
      if changes[:list_items],
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

    if changed_fields != [] do
      json_data = Map.merge(%{changed_fields: changed_fields}, additional_json_data)

      user_id_to_notification_fun = fn user_id ->
        %Sanbase.AppNotifications.Notification{
          type: "update_watchlist",
          user_id: user_id,
          actor_user_id: author_id,
          entity_type: "watchlist",
          entity_id: watchlist_id,
          is_broadcast: false,
          is_system_generated: false,
          json_data: json_data
        }
      end

      multi_insert_notifications(user_ids, user_id_to_notification_fun)
    end
  end

  defp multi_insert_notifications(user_ids, user_id_to_notification_fun) do
    user_ids
    |> Enum.reduce(Ecto.Multi.new(), fn user_id, multi ->
      Ecto.Multi.insert(multi, {:notification, user_id}, user_id_to_notification_fun.(user_id))
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, _operation, reason, _changes_so_far} -> {:error, reason}
    end
  end
end
