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

  @event_types ["create", "update"]
  # "publish_insight", "create/update user_trigger", "create/update public watchlist"
  @table "timeline_events"
  schema @table do
    field(:event_type, :string)
    belongs_to(:user, User)
    belongs_to(:post, Post)
    belongs_to(:user_list, UserList)
    belongs_to(:user_trigger, UserTrigger)

    field(:created_at, :utc_datetime)
  end

  def changeset(%__MODULE__{} = timeline_events, attrs \\ %{}) do
    attrs = Map.put(attrs, :created_at, Timex.now())

    timeline_events
    |> cast(attrs, [:event_type, :user_id, :post_id, :user_list_id, :user_trigger_id])
    |> unique_constraint(:post_id)
    |> unique_constraint(:user_list_id)
    |> unique_constraint(:user_trigger_id)
  end

  def create_event(%Post{id: id}, params) do
    create_event(:post_id, id, params)
  end

  def create_event(%UserList{id: id}, params) do
    create_event(:user_list_id, id, params)
  end

  def create_event(%UserTrigger{id: id}, params) do
    create_event(:user_trigger_id, id, params)
  end

  defp create_event(type, id, params) do
    %__MODULE__{} |> changeset(Map.put(params, type, id)) |> IO.inspect() |> Repo.insert()
  end
end
