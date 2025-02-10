defmodule Sanbase.Timeline.SeenEvent do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent

  schema "seen_timeline_events" do
    field(:seen_at, :utc_datetime)

    belongs_to(:user, User)
    belongs_to(:event, TimelineEvent)

    timestamps()
  end

  @doc false
  def changeset(seen_event, attrs) do
    seen_event
    |> cast(attrs, [:user_id, :event_id, :seen_at])
    |> validate_required([:user_id, :event_id, :seen_at])
  end

  def fetch_or_create(params) do
    params
    |> fetch()
    |> case do
      %__MODULE__{} = seen_event ->
        {:ok, seen_event}

      nil ->
        params = Map.put(params, :seen_at, DateTime.utc_now())

        %__MODULE__{}
        |> changeset(params)
        |> Repo.insert()
    end
  end

  def fetch(%{event_id: event_id, user_id: user_id}) do
    Repo.one(from(se in __MODULE__, where: se.user_id == ^user_id and se.event_id == ^event_id))
  end

  def last_seen_for_user(user_id) do
    Repo.one(from(se in __MODULE__, where: se.user_id == ^user_id, select: max(se.event_id)))
  end
end
