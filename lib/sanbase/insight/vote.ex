defmodule Sanbase.Insight.Vote do
  use Ecto.Schema
  use Timex.Ecto.Timestamps

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Insight.{Post, Vote}
  alias Sanbase.Auth.User

  schema "votes" do
    belongs_to(:post, Post)
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%Vote{} = vote, attrs \\ %{}) do
    vote
    |> cast(attrs, [:post_id, :user_id])
    |> validate_required([:post_id, :user_id])
    |> unique_constraint(:post_id, name: :votes_post_id_user_id_index)
  end

  def create(attrs) do
    %Vote{}
    |> Vote.changeset(attrs)
    |> Repo.insert()
  end

  def remove(%__MODULE__{} = vote) do
    Repo.delete(vote)
  end

  def get_by_opts(opts) when is_list(opts) do
    Repo.get_by(__MODULE__, opts)
  end
end
