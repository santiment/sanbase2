defmodule Sanbase.Timeline.TimelineEvent do
  @moduledoc ~s"""
  Module for insertting events when create/update insights, watchlists and triggers
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Following.UserFollower

  alias __MODULE__

  @publish_insight "publish_insight"
  @create_watchlist "create_watchlist"
  @create_public_trigger "create_public_trigger"
  @event_types [@publish_insight, @create_watchlist, @create_public_trigger]

  @table "timeline_events"
  schema @table do
    field(:event_type, :string)
    belongs_to(:user, User)
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)

    field(:created_at, :utc_datetime)
  end

  def publish_insight(), do: @publish_insight
  def create_watchlist(), do: @create_watchlist
  def create_public_trigger(), do: @create_public_trigger

  def create_changeset(%__MODULE__{} = timeline_events, attrs \\ %{}) do
    attrs = Map.put(attrs, :created_at, Timex.now())

    timeline_events
    |> cast(attrs, [:event_type, :user_id, :post_id, :user_list_id, :user_trigger_id, :created_at])
  end

  def events(
        %User{id: user_id},
        %{limit: limit, cursor: %{type: cursor_type, datetime: cursor_datetime}}
      ) do
    TimelineEvent
    |> events_by_followed_users(user_id, limit)
    |> by_cursor(cursor_type, cursor_datetime)
    |> Repo.all()
    |> events_with_cursor()
  end

  def events(%User{id: user_id}, %{limit: limit}) do
    TimelineEvent
    |> events_by_followed_users(user_id, limit)
    |> Repo.all()
    |> events_with_cursor()
    |> IO.inspect()
  end

  def events(_, _), do: {:error, "Bad arguments"}

  def create_event(%Post{id: id}, params) do
    create_event(:post_id, id, params)
  end

  def create_event(%UserList{id: id}, params) do
    create_event(:user_list_id, id, params)
  end

  def create_event(%UserTrigger{id: id}, params) do
    create_event(:user_trigger_id, id, params)
  end

  # private functions

  defp create_event(type, id, params) do
    %__MODULE__{} |> create_changeset(Map.put(params, type, id)) |> Repo.insert()
  end

  defp events_by_followed_users(query, user_id, limit) do
    following = UserFollower.following(user_id)

    from(
      te in query,
      where: te.user_id in ^following,
      order_by: [desc: te.created_at],
      limit: ^limit,
      preload: [:user_trigger, :post, :user_list, :user]
    )
  end

  defp by_cursor(query, :before, datetime) do
    from(
      te in query,
      where: te.created_at < ^datetime
    )
  end

  defp by_cursor(query, :after, datetime) do
    from(
      te in query,
      where: te.created_at > ^datetime
    )
  end

  defp events_with_cursor([]), do: {:ok, %{events: [], cursor: %{}}}

  defp events_with_cursor(events) do
    before_datetime = events |> List.last() |> Map.get(:created_at)
    after_datetime = events |> List.first() |> Map.get(:created_at)

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
