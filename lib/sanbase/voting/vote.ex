defmodule Sanbase.Vote do
  use Ecto.Schema
  use Timex.Ecto.Timestamps

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Insight.Post
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Auth.User

  schema "votes" do
    belongs_to(:post, Post)
    belongs_to(:timeline_event, TimelineEvent)
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = vote, attrs \\ %{}) do
    vote
    |> cast(attrs, [:post_id, :timeline_event_id, :user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:post_id,
      name: :votes_post_id_user_id_index
    )
    |> unique_constraint(:timeline_event_id,
      name: :votes_timeline_event_id_user_id_index
    )
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def remove(%__MODULE__{} = vote) do
    Repo.delete(vote)
  end

  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end
end
