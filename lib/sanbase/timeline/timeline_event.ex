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
  alias Sanbase.EctoHelper

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
    field(:payload, :map)

    belongs_to(:user, User)
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)

    has_many(:votes, Vote, on_delete: :delete_all)

    has_many(:event_comment_mapping, Sanbase.Timeline.TimelineEventComment, on_delete: :delete_all)

    has_many(:comments, through: [:event_comment_mapping, :comment])

    timestamps()
  end

  @type event_type() :: String.t()
  @type autor_type() :: :all | :followed | :sanfam | :own
  @type filter() :: %{
          author: autor_type(),
          watchlists: list(non_neg_integer()),
          assets: list(String.t())
        }
  @type cursor_type() :: :before | :after
  @type cursor() :: %{type: cursor_type(), datetime: DateTime.t()}
  @type order() :: :datetime | :author | :votes | :comments
  @type timeline_event_args :: %{
          limit: non_neg_integer(),
          cursor: cursor(),
          filter_by: filter(),
          order_by: order()
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

  def by_id(id) do
    from(te in TimelineEvent, where: te.id == ^id, preload: :votes)
    |> Repo.one()
  end

  @doc """
  Public events by sanfamily members.
  The events can be paginated with time-based cursor pagination.
  """
  def events(%{
        order_by: order_by,
        limit: limit,
        cursor: %{type: cursor_type, datetime: cursor_datetime}
      }) do
    TimelineEvent
    |> by_cursor(cursor_type, cursor_datetime)
    |> events_by_sanfamily_query()
    |> events_order_limit_preload_query(order_by, min(limit, @max_events_returned))
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(%{order_by: order_by, limit: limit}) do
    TimelineEvent
    |> events_by_sanfamily_query()
    |> events_order_limit_preload_query(order_by, min(limit, @max_events_returned))
    |> Repo.all()
    |> events_with_cursor()
  end

  @doc """
  Events by current user, followed users or sanfamily members.
  The events can be paginated with time-based cursor pagination.
  """
  @spec events(%User{}, timeline_event_args) :: {:ok, events_with_cursor} | {:error, String.t()}
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
    |> by_cursor(cursor_type, cursor_datetime)
    |> filter_by_query(filter_by, user_id)
    |> events_with_public_entities_query(user_id)
    |> events_order_limit_preload_query(order_by, min(limit, @max_events_returned))
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(%User{id: user_id}, %{order_by: order_by, filter_by: filter_by, limit: limit}) do
    TimelineEvent
    |> filter_by_query(filter_by, user_id)
    |> events_with_public_entities_query(user_id)
    |> events_order_limit_preload_query(order_by, min(limit, @max_events_returned))
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

  # show private and public entities only if they belong to current user, otherwise show only public entities
  defp events_with_public_entities_query(query, user_id) do
    from(
      event in query,
      left_join: ut in UserTrigger,
      on: event.user_trigger_id == ut.id,
      left_join: ul in UserList,
      on: event.user_list_id == ul.id,
      where:
        event.user_id == ^user_id or
          (event.user_id != ^user_id and
             (not is_nil(event.post_id) or
                ul.is_public == true or
                fragment("trigger->>'is_public' = 'true'")))
    )
  end

  defp filter_by_query(query, filter_by, user_id) do
    query
    |> filter_by_author_query(filter_by, user_id)
    |> filter_by_watchlists_query(filter_by)
    |> filter_by_assets_query(filter_by, user_id)
  end

  defp filter_by_author_query(query, %{author: :all}, user_id) do
    events_by_sanfamily_or_followed_users_or_own_query(query, user_id)
  end

  defp filter_by_author_query(query, %{author: :sanfam}, _) do
    events_by_sanfamily_query(query)
  end

  defp filter_by_author_query(query, %{author: :followed}, user_id) do
    events_by_followed_users_query(query, user_id)
  end

  defp filter_by_author_query(query, %{author: :own}, user_id) do
    events_by_current_user_query(query, user_id)
  end

  defp filter_by_author_query(query, _, user_id) do
    events_by_sanfamily_or_followed_users_or_own_query(query, user_id)
  end

  defp filter_by_watchlists_query(query, %{watchlists: watchlists})
       when is_list(watchlists) and length(watchlists) > 0 do
    from(event in query, where: event.user_list_id in ^watchlists)
  end

  defp filter_by_watchlists_query(query, _), do: query

  defp filter_by_assets_query(query, %{assets: assets} = filter_by, user_id)
       when is_list(assets) and length(assets) > 0 do
    {slugs, tickers} = get_slugs_and_tickers_by_asset_list(assets)
    watchlist_ids = get_watchlist_ids_by_asset_list(assets, filter_by, user_id)
    insight_ids = get_insight_ids_by_asset_list({slugs, tickers}, filter_by, user_id)
    trigger_ids = get_trigger_ids_by_asset_list({slugs, tickers}, filter_by, user_id)

    from(event in query,
      where:
        event.user_list_id in ^watchlist_ids or
          event.post_id in ^insight_ids or
          event.user_trigger_id in ^trigger_ids
    )
  end

  defp filter_by_assets_query(query, _, _), do: query

  defp get_watchlist_ids_by_asset_list(assets, filter_by, user_id) do
    from(
      entity in UserList,
      join: li in assoc(entity, :list_items),
      where: li.project_id in ^assets,
      select: entity.id
    )
    |> filter_by_author_query(filter_by, user_id)
    |> Repo.all()
  end

  defp get_slugs_and_tickers_by_asset_list(assets) do
    project_slugs_and_tickers =
      from(p in Sanbase.Model.Project, where: p.id in ^assets, select: [p.slug, p.ticker])
      |> Repo.all()

    slugs = project_slugs_and_tickers |> Enum.map(fn [slug, _] -> slug end)
    tickers = project_slugs_and_tickers |> Enum.map(fn [_, ticker] -> ticker end)

    {slugs, tickers}
  end

  defp get_insight_ids_by_asset_list({slugs, tickers}, filter_by, user_id) do
    from(
      entity in Post,
      join: t in assoc(entity, :tags),
      where: t.name in ^slugs or t.name in ^tickers,
      select: entity.id
    )
    |> filter_by_author_query(filter_by, user_id)
    |> Repo.all()
  end

  defp get_trigger_ids_by_asset_list({slugs, tickers}, filter_by, user_id) do
    triggers =
      from(ut in UserTrigger, select: [ut.id, fragment("trigger->'settings'->'target'")])
      |> filter_by_author_query(filter_by, user_id)
      |> Repo.all()

    triggers
    |> Enum.filter(fn
      [_, %{"slug" => slug}] when is_binary(slug) ->
        slug in slugs

      [_, %{"slug" => target_slugs}] when is_list(slugs) ->
        MapSet.new(target_slugs) |> MapSet.intersection(MapSet.new(slugs)) |> MapSet.size() > 0

      [_, %{"word" => word}] when is_binary(word) ->
        word in slugs or String.upcase(word) in tickers

      [_, %{"word" => words}] when is_list(words) ->
        words_upcase = words |> Enum.map(&String.upcase/1)

        MapSet.new(words) |> MapSet.intersection(MapSet.new(slugs)) |> MapSet.size() > 0 or
          MapSet.new(words_upcase) |> MapSet.intersection(MapSet.new(tickers)) |> MapSet.size() >
            0
    end)
    |> Enum.map(fn [id, _] -> id end)
  end

  defp events_by_sanfamily_or_followed_users_or_own_query(query, user_id) do
    sanclan_or_followed_users_or_own_ids =
      Sanbase.Auth.UserFollower.followed_by(user_id)
      |> Enum.map(& &1.id)
      |> Enum.concat(Sanbase.Auth.Role.san_family_ids())
      |> Enum.concat([user_id])
      |> Enum.dedup()

    from(
      event in query,
      where: event.user_id in ^sanclan_or_followed_users_or_own_ids
    )
  end

  defp events_by_sanfamily_query(query) do
    sanfamily_ids = Sanbase.Auth.Role.san_family_ids()

    from(
      event in query,
      where: event.user_id in ^sanfamily_ids
    )
  end

  defp events_by_followed_users_query(query, user_id) do
    followed_users_ids =
      Sanbase.Auth.UserFollower.followed_by(user_id)
      |> Enum.map(& &1.id)

    from(
      event in query,
      where: event.user_id in ^followed_users_ids
    )
  end

  defp events_by_current_user_query(query, user_id) do
    from(
      event in query,
      where: event.user_id == ^user_id
    )
  end

  defp events_order_limit_preload_query(query, order_by, limit) do
    query
    |> limit(^limit)
    |> order_by_query(order_by)
    |> preload([:user_trigger, [post: :tags], :user_list, :user, :votes])
  end

  defp order_by_query(query, :datetime) do
    from(
      event in query,
      order_by: [desc: event.inserted_at]
    )
  end

  defp order_by_query(query, :author) do
    from(
      event in query,
      join: u in assoc(event, :user),
      order_by: [asc: u.username, desc: event.inserted_at]
    )
  end

  defp order_by_query(query, :votes) do
    # order by: date, votes count, datetime
    ids =
      from(
        entity in query,
        left_join: assoc in assoc(entity, :votes),
        select: {entity.id, fragment("COUNT(?)", assoc.id)},
        group_by: entity.id,
        order_by:
          fragment(
            "?::date DESC, count DESC NULLS LAST, ? DESC",
            entity.inserted_at,
            entity.inserted_at
          )
      )
      |> Repo.all()
      |> Enum.map(fn {id, _} -> id end)

    EctoHelper.by_id_in_order_query(query, ids)
  end

  defp order_by_query(query, :comments) do
    ids = EctoHelper.fetch_ids_ordered_by_assoc_count(query, :comments)
    EctoHelper.by_id_in_order_query(query, ids)
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
