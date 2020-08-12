defmodule Sanbase.Auth.UserFollower do
  @moduledoc """
  Module implementing follow/unfollow functionality between users.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  @primary_key false
  @timestamps_opts [updated_at: false]
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
  def unfollow(user_id, user_id), do: {:error, "User can't unfollow oneself"}

  def unfollow(user_id, follower_id) do
    from(uf in __MODULE__, where: uf.user_id == ^user_id and uf.follower_id == ^follower_id)
    |> Repo.delete_all()
    |> case do
      {1, _} -> {:ok, "User successfully unfollowed"}
      _ -> {:error, "Error trying to unfollow user"}
    end
  end

  @doc """
  Returns all user ids of users that are followed by certain user
  """
  def followed_by(user_id) do
    from(
      uf in __MODULE__,
      inner_join: u in User,
      on: u.id == uf.user_id,
      where: uf.follower_id == ^user_id,
      select: u
    )
    |> Repo.all()
  end

  @doc """
  Returns all user ids of users that follow certain user
  """
  def followers_of(user_id) do
    from(
      uf in __MODULE__,
      inner_join: u in User,
      on: u.id == uf.follower_id,
      where: uf.user_id == ^user_id,
      select: u
    )
    |> Repo.all()
  end

  def user_id_to_followers_count() do
    from(
      uf in __MODULE__,
      select: {uf.user_id, count(uf.follower_id)},
      group_by: uf.user_id
    )
    |> Repo.all()
    |> Map.new()
  end
end
