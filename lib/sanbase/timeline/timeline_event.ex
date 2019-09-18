defmodule Sanbase.Timeline.TimelineEvent do
  @moduledoc ~s"""
  Persisting events on create/update insights, watchlists and triggers
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Signal.UserTrigger
  alias Sanbase.Following.UserFollower

  alias __MODULE__

  @doc """
  Currently supported events are:
  * Publish Insight
  * Update a public Watchlist with projects
  * Create a public UserTrigger
  """
  @publish_insight_type "publish_insight"
  @update_watchlist_type "update_watchlist"
  @create_public_trigger_type "create_public_trigger"

  @max_events_returned 100

  @timestamps_opts [updated_at: false, type: :utc_datetime]
  @table "timeline_events"
  schema @table do
    field(:event_type, :string)
    belongs_to(:user, User)
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)

    timestamps()
  end

  @type event_type() :: String.t()
  @type cursor_type() :: :before | :after
  @type cursor() :: %{type: cursor_type(), datetime: DateTime.t()}
  @type cursor_with_limit :: %{
          limit: non_neg_integer(),
          cursor: cursor()
        }
  @type events_with_cursor ::
          %{
            events: list(%TimelineEvent{}),
            cursor: %{
              before: DateTime.t(),
              after: DateTime.t()
            }
          }

  def publish_insight_type(), do: @publish_insight_type
  def update_watchlist_type(), do: @update_watchlist_type
  def create_public_trigger_type(), do: @create_public_trigger_type

  def create_changeset(%__MODULE__{} = timeline_events, attrs \\ %{}) do
    timeline_events
    |> cast(attrs, [
      :event_type,
      :user_id,
      :post_id,
      :user_list_id,
      :user_trigger_id,
      :inserted_at
    ])
    |> validate_required([:event_type, :user_id])
  end

  @doc """
  Returns the generated eventsb by the activity of followed users.
  The events can be paginated with time-based cursor pagination.
  """
  @spec events(%User{}, cursor_with_limit) :: {:ok, events_with_cursor} | {:error, String.t()}
  def events(
        %User{id: user_id},
        %{limit: limit, cursor: %{type: cursor_type, datetime: cursor_datetime}}
      ) do
    TimelineEvent
    |> events_by_followed_users(user_id, min(limit, @max_events_returned))
    |> by_cursor(cursor_type, cursor_datetime)
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(%User{id: user_id}, %{limit: limit}) do
    TimelineEvent
    |> events_by_followed_users(user_id, min(limit, @max_events_returned))
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(_, _), do: {:error, "Bad arguments"}

  @doc """
  Asynchronously create a timeline event only if all criterias are met.

  Params:
    - event_type: one of the currently supported event type listed above.
    - resource: created/updated resource. Currently supported: Post, UserList, UserTrigger.
    - changeset: the changes used to determine if an event should be created.
  """
  @spec maybe_create_event_async(
          event_type,
          %Post{} | %UserList{} | %UserTrigger{},
          Ecto.Changeset.t()
        ) :: Task.t()
  def maybe_create_event_async(event_type, resource, changeset) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      maybe_create_event(resource, changeset.changes, %{
        event_type: event_type,
        user_id: resource.user_id
      })
    end)
  end

  # private functions

  defp maybe_create_event(
         %Post{id: id, ready_state: "published"},
         %{state: "approved"},
         %{event_type: @publish_insight_type} = params
       ) do
    create_event(:post_id, id, params)
  end

  defp maybe_create_event(
         %Post{id: id, state: "approved"},
         %{ready_state: "published"},
         %{event_type: @publish_insight_type} = params
       ) do
    create_event(:post_id, id, params)
  end

  defp maybe_create_event(%Post{id: _id}, _, _), do: :ok

  defp maybe_create_event(
         %UserList{id: id, is_public: true},
         %{list_items: list_items},
         %{event_type: @update_watchlist_type} = params
       )
       when is_list(list_items) and length(list_items) > 0 do
    create_event(:user_list_id, id, params)
  end

  defp maybe_create_event(%UserList{id: _id}, _, _), do: :ok

  defp maybe_create_event(
         %UserTrigger{id: id, trigger: %{is_public: true}},
         _,
         %{event_type: @create_public_trigger_type} = params
       ) do
    create_event(:user_trigger_id, id, params)
  end

  defp maybe_create_event(%UserTrigger{id: _id}, _, _), do: :ok

  defp create_event(type, id, params) do
    %__MODULE__{} |> create_changeset(Map.put(params, type, id)) |> Repo.insert()
  end

  defp events_by_followed_users(query, user_id, limit) do
    following = UserFollower.followed_by(user_id)

    from(
      event in query,
      where: event.user_id in ^following,
      order_by: [desc: event.inserted_at],
      limit: ^limit,
      preload: [:user_trigger, :post, :user_list, :user]
    )
  end

  defp by_cursor(query, :before, datetime) do
    from(
      event in query,
      where: event.inserted_at < ^datetime
    )
  end

  defp by_cursor(query, :after, datetime) do
    from(
      event in query,
      where: event.inserted_at > ^datetime
    )
  end

  defp events_with_cursor([]), do: {:ok, %{events: [], cursor: %{}}}

  defp events_with_cursor(events) do
    before_datetime = events |> List.last() |> Map.get(:inserted_at)
    after_datetime = events |> List.first() |> Map.get(:inserted_at)

    {:ok,
     %{
       events: events,
       cursor: %{
         before: before_datetime,
         after: after_datetime
       }
     }}
  end
end
