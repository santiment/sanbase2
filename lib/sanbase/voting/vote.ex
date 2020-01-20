defmodule Sanbase.Vote do
  @moduledoc """
  Module for voting for insights and timeline events.
  """
  use Ecto.Schema
  use Timex.Ecto.Timestamps

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Insight.Post
  alias Sanbase.Timeline.TimelineEvent
  alias Sanbase.Auth.User

  @type vote_params :: %{
          :user_id => non_neg_integer(),
          optional(:timeline_event_id) => non_neg_integer(),
          optional(:post_id) => non_neg_integer()
        }

  @type vote_kw_list_params :: [
          user_id: non_neg_integer(),
          timeline_event_id: non_neg_integer(),
          post_id: non_neg_integer()
        ]

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

  @spec create(vote_params) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    # Voting is idempotent - this fixes voting again due to caching
    |> Repo.insert(on_conflict: :nothing)
  end

  @spec remove(%__MODULE__{}) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def remove(%__MODULE__{} = vote) do
    Repo.delete(vote)
  end

  @spec get_by_opts(vote_kw_list_params) :: %__MODULE__{} | nil
  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end
end
