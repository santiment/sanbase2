defmodule Sanbase.Intercom.UserEvent do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Auth.User

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

  def get_last_intercom_event_timestamp(user_id) do
    from(
      ue in __MODULE__,
      where: ue.user_id == ^user_id and not is_nil(ue.remote_id),
      order_by: [desc: ue.created_at],
      limit: 1,
      select: ue.created_at
    )
    |> Repo.one()
    |> case do
      %DateTime{} = created_at -> DateTime.to_unix(created_at, :millisecond)
      nil -> nil
    end
  end

  def sync_events_from_intercom() do
    Logger.info("Start sync_events_from_intercom")

    # Skip if api key not present in env. (Run only on production)
    if Sanbase.Intercom.intercom_api_key() do
      User
      |> Repo.all()
      |> Enum.map(& &1.id)
      |> Enum.each(fn user_id ->
        since = get_last_intercom_event_timestamp(user_id)
        sync_with_intercom(user_id, since)
      end)

      Logger.info("Finish sync_events_from_intercom")
    else
      :ok
    end
  end

  def get_events_for_users(user_ids, from, to) do
    from(ue in __MODULE__,
      where:
        ue.user_id in ^user_ids and
          ue.created_at >= ^from and
          ue.created_at <= ^to
    )
    |> Repo.all()
  end

  # helpers

  defp sync_with_intercom(user_id, since \\ nil) do
    Sanbase.Intercom.get_events_for_user(user_id, since)
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
