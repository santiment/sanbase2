defmodule Sanbase.Intercom.UserEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo

  schema "user_events" do
    field(:created_at, :utc_datetime)
    field(:event_name, :string)
    field(:metadata, :map, default: %{})
    field(:remote_id, :string)

    belongs_to(:user, Sanbase.Auth.User)
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_event, attrs) do
    user_event
    |> cast(attrs, [:user_id, :event_name, :created_at, :metadata, :remote_id])
    |> validate_required([:user_id, :event_name, :created_at])
  end

  def create([]), do: :ok

  def create(events) when is_list(events) do
    Repo.insert_all(__MODULE__, events, on_conflict: :nothing)
  end

  def sync_with_intercom(user_id) do
    Sanbase.Intercom.get_events_for_user(user_id)
    |> Enum.map(fn %{
                     "created_at" => created_at,
                     "event_name" => event_name,
                     "id" => remote_id,
                     "metadata" => metadata
                   } ->
      %{
        user_id: user_id,
        event_name: event_name,
        created_at: DateTime.from_unix!(created_at),
        metadata: metadata,
        remote_id: remote_id,
        inserted_at: Timex.now() |> DateTime.truncate(:second),
        updated_at: Timex.now() |> DateTime.truncate(:second)
      }
    end)
    |> create()
  end
end
