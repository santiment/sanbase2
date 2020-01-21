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
  alias Sanbase.Vote

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
  @trigger_fired "trigger_fired"

  @max_events_returned 100

  @timestamps_opts [updated_at: false, type: :utc_datetime]
  @table "timeline_events"
  schema @table do
    field(:event_type, :string)
    belongs_to(:user, User)
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)
    has_many(:votes, Vote, on_delete: :delete_all)
    field(:payload, :map)

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
  @type fired_triggers_map :: %{
          user_trigger_id: non_neg_integer(),
          user_id: non_neg_integer(),
          payload: map(),
          triggered_at: DateTime.t()
        }

  def publish_insight_type(), do: @publish_insight_type
  def update_watchlist_type(), do: @update_watchlist_type
  def create_public_trigger_type(), do: @create_public_trigger_type
  def trigger_fired(), do: @trigger_fired

  def create_changeset(%__MODULE__{} = timeline_events, attrs \\ %{}) do
    timeline_events
    |> cast(attrs, [
      :event_type,
      :user_id,
      :post_id,
      :user_list_id,
      :user_trigger_id,
      :payload,
      :inserted_at
    ])
    |> validate_required([:event_type, :user_id])
  end

  def events(%{limit: limit, cursor: %{type: cursor_type, datetime: cursor_datetime}}) do
    TimelineEvent
    |> events_by_sanfamily()
    |> events_order_limit_preload_query(min(limit, @max_events_returned))
    |> by_cursor(cursor_type, cursor_datetime)
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(%{limit: limit}) do
    TimelineEvent
    |> events_by_sanfamily()
    |> events_order_limit_preload_query(min(limit, @max_events_returned))
    |> Repo.all()
    |> events_with_cursor()
  end

  def by_id(id) do
    from(te in TimelineEvent, where: te.id == ^id, preload: :votes)
    |> Repo.one()
  end

  @doc """
  Returns the generated events by the activity of followed users.
  The events can be paginated with time-based cursor pagination.
  """
  @spec events(%User{}, cursor_with_limit) :: {:ok, events_with_cursor} | {:error, String.t()}
  def events(
        %User{id: user_id},
        %{limit: limit, cursor: %{type: cursor_type, datetime: cursor_datetime}}
      ) do
    TimelineEvent
    |> events_by_sanfamily_or_followed_users_query(user_id)
    |> user_fired_signals_query(user_id)
    |> events_with_public_entities_query()
    |> events_order_limit_preload_query(min(limit, @max_events_returned))
    |> by_cursor(cursor_type, cursor_datetime)
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(%User{id: user_id}, %{limit: limit}) do
    TimelineEvent
    |> events_by_sanfamily_or_followed_users_query(user_id)
    |> user_fired_signals_query(user_id)
    |> events_with_public_entities_query()
    |> events_order_limit_preload_query(min(limit, @max_events_returned))
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
  def maybe_create_event_async(
        event_type,
        resource,
        %Ecto.Changeset{} = changeset
      ) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      maybe_create_event(resource, changeset.changes, %{
        event_type: event_type,
        user_id: resource.user_id
      })
    end)
  end

  @spec create_trigger_fired_events(list(fired_triggers_map)) :: Task.t()
  def create_trigger_fired_events(fired_triggers) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      fired_triggers
      |> Enum.map(fn %{
                       user_trigger_id: user_trigger_id,
                       user_id: user_id,
                       payload: payload,
                       triggered_at: triggered_at
                     } ->
        %{
          event_type: @trigger_fired,
          user_trigger_id: user_trigger_id,
          user_id: user_id,
          payload: payload,
          inserted_at: triggered_at
        }
      end)
      |> Enum.chunk_every(200)
      |> Enum.each(fn chunk ->
        Sanbase.Repo.insert_all(__MODULE__, chunk)
      end)
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

  defp events_with_public_entities_query(query) do
    from(
      event in query,
      left_join: ut in UserTrigger,
      on: event.user_trigger_id == ut.id,
      left_join: ul in UserList,
      on: event.user_list_id == ul.id,
      where:
        not is_nil(event.post_id) or
          ul.is_public == true or
          fragment("trigger->>'is_public' = 'true'")
    )
  end

  defp events_order_limit_preload_query(query, limit) do
    from(
      event in query,
      order_by: [desc: event.inserted_at],
      limit: ^limit,
      preload: [:user_trigger, [post: :tags], :user_list, :user, :votes]
    )
  end

  defp events_by_sanfamily(query) do
    sanfamily_ids = Sanbase.Auth.Role.san_family_ids()

    from(
      event in query,
      where: event.user_id in ^sanfamily_ids
    )
  end

  defp events_by_sanfamily_or_followed_users_query(query, user_id) do
    sanclan_or_followed_users_ids =
      Sanbase.Auth.UserFollower.followed_by(user_id)
      |> Enum.map(& &1.id)
      |> Enum.concat(Sanbase.Auth.Role.san_family_ids())
      |> Enum.dedup()

    from(
      event in query,
      where: event.user_id in ^sanclan_or_followed_users_ids
    )
  end

  def user_fired_signals_query(query, user_id) do
    from(
      event in query,
      or_where: event.event_type == ^@trigger_fired and event.user_id == ^user_id
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
