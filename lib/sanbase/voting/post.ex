defmodule Sanbase.Voting.Post do
  use Ecto.Schema
  import Ecto.Changeset
  use Timex.Ecto.Timestamps

  alias Sanbase.Voting.{Poll, Post, Vote}
  alias Sanbase.Auth.User

  @approved "approved"
  @declined "declined"

  schema "posts" do
    belongs_to(:poll, Poll)
    belongs_to(:user, User)
    has_many(:votes, Vote, on_delete: :delete_all)

    field(:title, :string)
    field(:link, :string)
    field(:state, :string)
    field(:moderation_comment, :string)

    timestamps()
  end

  def create_changeset(%Post{} = post, attrs) do
    post
    |> cast(attrs, [:title, :link])
    |> validate_required([:poll_id, :user_id, :title, :link])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def changeset(%Post{} = post, attrs \\ %{}) do
    post
    |> cast(attrs, [:title, :link, :state, :moderation_comment])
    |> validate_required([:poll_id, :user_id, :title, :link])
    |> validate_length(:title, max: 140)
    |> unique_constraint(:poll_id, name: :posts_poll_id_title_index)
  end

  def approved_state(), do: @approved

  def declined_state(), do: @declined
end
