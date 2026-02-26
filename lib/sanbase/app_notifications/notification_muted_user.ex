defmodule Sanbase.AppNotifications.NotificationMutedUser do
  @moduledoc """
  Schema for muting notifications from specific users.

  When user A mutes user B, future notifications triggered by B's actions
  are silently dropped for A. Existing notifications are unchanged.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @self_mute_message "Cannot mute yourself"

  @primary_key false
  @timestamps_opts [updated_at: false]
  schema "notification_muted_users" do
    belongs_to(:user, User, foreign_key: :user_id, primary_key: true)
    belongs_to(:muted_user, User, foreign_key: :muted_user_id, primary_key: true)
    timestamps()
  end

  def changeset(%__MODULE__{} = muted_user, attrs) do
    muted_user
    |> cast(attrs, [:user_id, :muted_user_id])
    |> validate_required([:user_id, :muted_user_id])
    |> unique_constraint([:user_id, :muted_user_id],
      name: :notification_muted_users_pkey
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:muted_user_id)
    |> validate_not_self_mute()
    |> check_constraint(:user_id, name: :cannot_mute_self, message: @self_mute_message)
  end

  defp validate_not_self_mute(changeset) do
    user_id = get_field(changeset, :user_id)
    muted_user_id = get_field(changeset, :muted_user_id)

    if user_id && muted_user_id && user_id == muted_user_id do
      add_error(changeset, :user_id, @self_mute_message)
    else
      changeset
    end
  end

  @doc """
  Mute notifications from `muted_user_id` for `user_id`.
  Returns `{:error, "Cannot mute yourself"}` if both IDs are equal.
  """
  def mute(user_id, user_id), do: {:error, @self_mute_message}

  def mute(user_id, muted_user_id) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, muted_user_id: muted_user_id})
    |> Repo.insert()
  end

  @doc """
  Unmute notifications from `muted_user_id` for `user_id`.
  """
  def unmute(user_id, muted_user_id) do
    from(m in __MODULE__,
      where: m.user_id == ^user_id and m.muted_user_id == ^muted_user_id
    )
    |> Repo.one()
    |> case do
      %__MODULE__{} = record ->
        Repo.delete(record)

      nil ->
        {:error, "User is not muted"}
    end
  end

  @doc """
  List all users muted by `user_id`. Returns a list of `%User{}` structs.
  """
  def list_muted_users(user_id) do
    from(m in __MODULE__,
      inner_join: u in User,
      on: u.id == m.muted_user_id,
      where: m.user_id == ^user_id,
      select: u
    )
    |> Repo.all()
  end

  @doc """
  Return a MapSet of user IDs that have muted `actor_user_id`.

  Used to filter notification recipients — if a user has muted the actor,
  they should not receive notifications triggered by that actor's actions.
  """
  def user_ids_that_muted(actor_user_id) do
    from(m in __MODULE__,
      where: m.muted_user_id == ^actor_user_id,
      select: m.user_id
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
