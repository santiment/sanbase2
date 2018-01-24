defmodule Sanbase.Voting.Vote do
  use Ecto.Schema
  import Ecto.Changeset
  use Timex.Ecto.Timestamps

  alias Sanbase.Voting.{Post, Vote}
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
end
