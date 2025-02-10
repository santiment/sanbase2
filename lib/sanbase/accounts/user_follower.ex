defmodule Sanbase.Accounts.UserFollower do
  @moduledoc """
  Module implementing follow/unfollow functionality between users.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @primary_key false
  @timestamps_opts [updated_at: false]
  schema "user_followers" do
    belongs_to(:user, User, foreign_key: :user_id, primary_key: true)
    belongs_to(:follower, User, foreign_key: :follower_id, primary_key: true)
    field(:is_notification_disabled, :boolean, default: false)
    timestamps()
  end

  def changeset(%__MODULE__{} = user_follower, attrs \\ %{}) do
    user_follower
    |> cast(attrs, [:user_id, :follower_id, :is_notification_disabled])
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
    end
  end

  def following_toggle_notification(user_id, follower_id, disable_notifications) when user_id != follower_id do
    from(uf in __MODULE__, where: uf.user_id == ^user_id and uf.follower_id == ^follower_id)
    |> Repo.one()
    |> case do
      %__MODULE__{} = user_follower ->
        user_follower
        |> changeset(%{is_notification_disabled: disable_notifications})
        |> Repo.update()

      nil ->
        {:error, "This user is not followed!"}
    end
  end

  @doc """
  Returns all user ids of users that are followed by certain user
  """
  def followed_by(user_id) do
    Repo.all(
      from(uf in __MODULE__, inner_join: u in User, on: u.id == uf.user_id, where: uf.follower_id == ^user_id, select: u)
    )
  end

  def followed_by2(user_id) do
    Repo.all(from(uf in __MODULE__, where: uf.follower_id == ^user_id, preload: [:user]))
  end

  def followed_by_with_notifications_enabled(user_id) do
    Repo.all(
      from(uf in __MODULE__,
        inner_join: u in User,
        on: u.id == uf.user_id,
        where: uf.follower_id == ^user_id and uf.is_notification_disabled != true,
        select: u
      )
    )
  end

  @doc """
  Returns all user ids of users that follow certain user
  """
  def followers_of(user_id) do
    Repo.all(
      from(uf in __MODULE__, inner_join: u in User, on: u.id == uf.follower_id, where: uf.user_id == ^user_id, select: u)
    )
  end

  def followers_of2(user_id) do
    from(
      uf in __MODULE__,
      where: uf.user_id == ^user_id,
      preload: [:follower]
    )
    |> Repo.all()
    |> Enum.map(fn uf ->
      %{user: uf.follower, is_notification_disabled: uf.is_notification_disabled}
    end)
  end

  def user_id_to_followers_count do
    from(
      uf in __MODULE__,
      select: {uf.user_id, count(uf.follower_id)},
      group_by: uf.user_id
    )
    |> Repo.all()
    |> Map.new()
  end

  # helpers

  defp get_pair(user_id, follower_id) do
    from(uf in __MODULE__, where: uf.user_id == ^user_id and uf.follower_id == ^follower_id)
    |> Repo.one()
    |> case do
      %__MODULE__{} = uf -> {:ok, uf}
      nil -> {:error, "User with id #{user_id} is not followed by user with id #{follower_id}"}
    end
  end
end
