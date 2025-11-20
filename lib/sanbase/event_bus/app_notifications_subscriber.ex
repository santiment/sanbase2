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
         %{data: %{event_type: :publish_insight, user_id: user_id, insight_id: insight_id}},
         event_shadow,
         state
       ) do
    create_notification(
      :publish_insight,
      followers_user_ids(user_id),
      %{insight_id: insight_id, author_id: user_id}
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
    Sanbase.Follower.followed_by_user_ids(user_id)
  end

  ## Insight notifications
  defp create_notification(:publish_insight, user_ids, %{
         insight_id: insight_id,
         author_id: author_id
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
         author_id: author_id
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
