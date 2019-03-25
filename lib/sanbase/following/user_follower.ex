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

  def follow(user_id, follower_id) when user_id != follower_id do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, follower_id: follower_id})
    |> Repo.insert()
  end

  def follow(_, _), do: {:error, "User can't follow oneself"}

  def unfollow(user_id, follower_id) when user_id != follower_id do
    from(uf in __MODULE__, where: uf.user_id == ^user_id and uf.follower_id == ^follower_id)
    |> Repo.delete_all()
    |> case do
      {1, _} -> {:ok, "User successfully unfollowed"}
      _ -> {:error, "Error trying to unfollow user"}
    end
  end

  def unfollow(_, _), do: {:error, "User can't unfollow oneself"}

  def get_following_user_ids(user_id) do
    user_id
    |> load_user()
    |> Map.get(:following)
    |> Enum.map(&Map.get(&1, :user_id))
  end

  def get_followers_user_ids(user_id) do
    user_id
    |> load_user()
    |> Map.get(:followers)
    |> Enum.map(&Map.get(&1, :follower_id))
  end

  # Private functions

  defp load_user(user_id) do
    User
    |> Repo.get(user_id)
    |> Repo.preload([:following, :followers])
  end
end
