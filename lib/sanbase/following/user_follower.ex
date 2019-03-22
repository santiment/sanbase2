defmodule Sanbase.Following.UserFollower do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  @primary_key false
  schema "user_followers" do
    belongs_to(:user, User, foreign_key: :user_id, primary_key: true)
    belongs_to(:follower, User, foreign_key: :follower_id, primary_key: true)
    timestamps()
  end

  def changeset(%__MODULE__{} = user_follower, attrs \\ %{}) do
    user_follower
    |> cast(attrs, [:user_id, :follower_id])
    |> unique_constraint(:user_id_follower_id, name: :user_followers_user_id_follower_id_index)
  end

  def follow(user_id, follower_id) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, follower_id: follower_id})
    |> Repo.insert()
  end

  def unfollow(user_id, follower_id) do
    from(uf in __MODULE__, where: uf.user_id == ^user_id and uf.follower_id == ^follower_id)
    |> Repo.delete_all()
  end
end
