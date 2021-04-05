defmodule Sanbase.Accounts.UserFollower do
  @moduledoc """
  Module implementing follow/unfollow functionality between users.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.User
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
    |> emit_event(:follow_user, %{})
  end

  def follow(_, _), do: {:error, "User can't follow oneself"}
  def unfollow(user_id, user_id), do: {:error, "User can't unfollow oneself"}

  def unfollow(user_id, follower_id) do
    with {:ok, user_follower} <- get_pair(user_id, follower_id),
         {:ok, _} <- Repo.delete(user_follower) do
      emit_event({:ok, user_follower}, :unfollow_user, %{})
      {:ok, "User successfully unfollowed"}
    else
      error -> error
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

  defp get_pair(user_id, follower_id) do
    from(uf in __MODULE__, where: uf.user_id == ^user_id and uf.follower_id == ^follower_id)
    |> Repo.one()
    |> case do
      %__MODULE__{} = uf -> {:ok, uf}
      nil -> {:error, "User with id #{user_id} is not followed by user with id #{follower_id}"}
    end
  end
end
