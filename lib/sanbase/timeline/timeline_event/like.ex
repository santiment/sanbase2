defmodule Sanbase.TimelineEvent.Like do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Auth.User

  @type timeline_event_like_params :: %{
          user_id: non_neg_integer(),
          timeline_event_id: non_neg_integer()
        }

  @table "timeline_event_likes"
  schema @table do
    belongs_to(:timeline_event, TimelineEvent)
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = like, attrs \\ %{}) do
    like
    |> cast(attrs, [:timeline_event_id, :user_id])
    |> validate_required([:timeline_event_id, :user_id])
    |> unique_constraint(:timeline_event_id,
      name: :timeline_event_likes_timeline_event_id_user_id_index
    )
  end

  @spec like(timeline_event_like_params) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def like(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  @spec unlike(timeline_event_like_params) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def unlike(%{user_id: user_id, timeline_event_id: timeline_event_id}) do
    get_by_opts(user_id: user_id, timeline_event_id: timeline_event_id)
    |> Repo.delete()
  end

  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end
end
