defmodule Sanbase.Timeline.TimelineEvent do
  @moduledoc ~s"""
  Persisting events on create/update insights, watchlists and triggers
  """
  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Alert.UserTrigger
  alias Sanbase.Vote
  alias Sanbase.Timeline.{Query, Filter, Order, Cursor, Type, PostProcess}

  alias __MODULE__

  @doc """
  Currently supported events are:
  * Publish Insight
  * Update a public Watchlist with projects
  * Create a public UserTrigger
  * Alert for UserTrigger fires
  """
  @publish_insight_type "publish_insight"
  @update_watchlist_type "update_watchlist"
  @create_public_trigger_type "create_public_trigger"
  @trigger_fired "trigger_fired"

  @max_events_returned 100

  @timestamps_opts [updated_at: false]
  @table "timeline_events"
  schema @table do
    field(:event_type, :string)
    field(:payload, :map)
    field(:data, :map)
    field(:tags, {:array, :string}, default: [], virtual: true)

    belongs_to(:user, User)
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)

    has_many(:votes, Vote, on_delete: :delete_all)

    has_many(:event_comment_mapping, Sanbase.Comment.TimelineEventComment, on_delete: :delete_all)

    has_many(:comments, through: [:event_comment_mapping, :comment])

    timestamps()
  end

  def publish_insight_type(), do: @publish_insight_type
  def update_watchlist_type(), do: @update_watchlist_type
  def create_public_trigger_type(), do: @create_public_trigger_type
  def trigger_fired(), do: @trigger_fired

  def create_changeset(%__MODULE__{} = timeline_events, attrs \\ %{}) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    timeline_events
    |> cast(attrs, [
      :event_type,
      :user_id,
      :post_id,
      :user_list_id,
      :user_trigger_id,
      :payload,
      :data,
      :inserted_at
    ])
    |> validate_required([:event_type, :user_id])
  end

  @by_id_preloads [:user_trigger, [post: :tags], :user_list, :user, :votes]

  @impl Sanbase.Entity.Behaviour
  def by_id!(id, opts), do: by_id(id, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_id(id, _opts) when is_integer(id) do
    from(te in TimelineEvent,
      where: te.id == ^id,
      preload: ^@by_id_preloads
    )
    |> Repo.one()
    |> case do
      %__MODULE__{} = result -> {:ok, result}
      nil -> {:error, "Timeline event with id #{id} does not exist"}
    end
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts) when is_list(ids), do: by_ids(ids, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(ids, _opts) when is_list(ids) do
    result =
      from(te in TimelineEvent,
        where: te.id in ^ids,
        preload: ^@by_id_preloads,
        order_by: fragment("array_position(?, ?::int)", ^ids, te.id)
      )
      |> Repo.all()

    {:ok, result}
  end

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(_opts) do
    from(te in __MODULE__)
    |> Query.events_with_public_entities_query()
    |> select([te], te.id)
  end

  @doc """
  Public events by sanfamily members.
  The events can be paginated with time-based cursor pagination.
  """
  def events(%{
        order_by: order_by,
        filter_by: filter_by,
        limit: limit,
        cursor: %{type: cursor_type, datetime: cursor_datetime}
      }) do
    TimelineEvent
    |> Cursor.filter_by_cursor(cursor_type, cursor_datetime)
    |> Filter.filter_by_query(filter_by)
    |> Query.events_by_sanfamily_query()
    |> Query.events_with_public_entities_query()
    |> Query.events_with_event_type([@publish_insight_type, @trigger_fired])
    |> Order.events_order_limit_preload_query(
      order_by,
      min(limit, @max_events_returned)
    )
    |> Repo.all()
    |> PostProcess.tag()
    |> Cursor.wrap_events_with_cursor()
  end

  def events(%{order_by: order_by, filter_by: filter_by, limit: limit}) do
    TimelineEvent
    |> Cursor.filter_by_min_dt()
    |> Filter.filter_by_query(filter_by)
    |> Query.events_by_sanfamily_query()
    |> Query.events_with_public_entities_query()
    |> Query.events_with_event_type([@publish_insight_type, @trigger_fired])
    |> Order.events_order_limit_preload_query(
      order_by,
      min(limit, @max_events_returned)
    )
    |> Repo.all()
    |> PostProcess.tag()
    |> Cursor.wrap_events_with_cursor()
  end

  @doc """
  Events by current user, followed users or sanfamily members.
  The events can be paginated with time-based cursor pagination.
  """
  @spec events(%User{}, Type.timeline_event_args()) ::
          {:ok, Type.events_with_cursor()} | {:error, String.t()}
  def events(
        %User{id: user_id},
        %{
          order_by: order_by,
          filter_by: filter_by,
          limit: limit,
          cursor: %{type: cursor_type, datetime: cursor_datetime}
        }
      ) do
    TimelineEvent
    |> Cursor.filter_by_cursor(cursor_type, cursor_datetime)
    |> Filter.filter_by_query(filter_by, user_id)
    |> Query.events_with_public_entities_query(user_id)
    |> Query.events_with_event_type([@publish_insight_type, @trigger_fired])
    |> Order.events_order_limit_preload_query(
      order_by,
      min(limit, @max_events_returned)
    )
    |> Repo.all()
    |> PostProcess.tag(user_id)
    |> Cursor.wrap_events_with_cursor()
  end

  def events(%User{id: user_id}, %{
        order_by: order_by,
        filter_by: filter_by,
        limit: limit
      }) do
    TimelineEvent
    |> Cursor.filter_by_min_dt()
    |> Filter.filter_by_query(filter_by, user_id)
    |> Query.events_with_public_entities_query(user_id)
    |> Query.events_with_event_type([@publish_insight_type, @trigger_fired])
    |> Order.events_order_limit_preload_query(
      order_by,
      min(limit, @max_events_returned)
    )
    |> Repo.all()
    |> PostProcess.tag(user_id)
    |> Cursor.wrap_events_with_cursor()
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
          Type.event_type(),
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

  @spec create_trigger_fired_events(list(Type.fired_triggers_map())) :: Task.t()
  def create_trigger_fired_events(fired_triggers) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      fired_triggers
      |> Enum.map(fn %{
                       user_trigger_id: user_trigger_id,
                       user_id: user_id,
                       payload: payload,
                       data: data,
                       triggered_at: triggered_at
                     } ->
        %{
          event_type: @trigger_fired,
          user_trigger_id: user_trigger_id,
          user_id: user_id,
          payload: payload,
          data: data,
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
    %__MODULE__{}
    |> create_changeset(Map.put(params, type, id))
    |> Repo.insert()
  end
end
