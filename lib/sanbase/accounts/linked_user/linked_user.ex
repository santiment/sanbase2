defmodule Sanbase.Accounts.LinkedUser do
  @moduledoc ~s"""
  A module that exposes the linked_users database table.

  A LinkedUser is a pair of primary and secondary users. When
  authenticating, the secondary user will get the sanbase subscription
  of the primary user. The primary use can have 2 secondary users sharing
  their subscription. The idea is that companies can share seats on a
  single account to cut costs.
  """

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User

  @pro_max_secondary_users 3
  @pro_plus_max_secondary_users 5

  schema "linked_users" do
    belongs_to(:primary_user, User)
    belongs_to(:secondary_user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = lu, attrs) do
    lu
    |> cast(attrs, [:secondary_user_id, :primary_user_id])
    |> validate_required([:secondary_user_id, :primary_user_id])
    |> unique_constraint(:secondary_user_id)
  end

  def create(primary_user_id, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:secondary_users_count, fn _repo, _changes ->
      {:ok, count_secondaries(primary_user_id)}
    end)
    |> Ecto.Multi.run(:max_secondary_users_count, fn _repo, _changes ->
      case Sanbase.Billing.Subscription.user_sanbase_plan(primary_user_id) do
        nil -> {:error, "The user does not have a Sanbase plan."}
        "PRO" -> {:ok, @pro_max_secondary_users}
        "PRO_PLUS" -> {:ok, @pro_plus_max_secondary_users}
      end
    end)
    |> Ecto.Multi.run(:add_linked_users, fn _repo, changes ->
      case changes.secondary_users_count < changes.max_secondary_users_count do
        true ->
          create_link(primary_user_id, user_id)

        false ->
          {:error,
           "The maximum number of linked secondary users of #{changes.secondary_users_count} has been reached."}
      end
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{add_linked_users: result}} -> {:ok, result}
      {:error, _failed_op, error, _changes} -> {:error, error}
    end
  end

  def delete(primary_user_id, secondary_user_id) do
    lu =
      Sanbase.Repo.get_by(__MODULE__,
        primary_user_id: primary_user_id,
        secondary_user_id: secondary_user_id
      )

    case lu do
      %__MODULE__{} = lu -> Sanbase.Repo.delete(lu)
      nil -> {:error, "Users are not linked"}
    end
  end

  def get_primary_user(secondary_user_id) do
    lu =
      from(lu in __MODULE__,
        where: lu.secondary_user_id == ^secondary_user_id,
        preload: [:primary_user]
      )
      |> Sanbase.Repo.one()

    {:ok, lu && lu.primary_user}
  end

  def get_primary_user_id(secondary_user_id) do
    result =
      from(lu in __MODULE__,
        where: lu.secondary_user_id == ^secondary_user_id,
        select: lu.primary_user_id
      )
      |> Sanbase.Repo.one()

    case result do
      primary_user_id when is_integer(primary_user_id) -> {:ok, primary_user_id}
      nil -> {:error, "No linked user found for user_id: #{secondary_user_id}"}
    end
  end

  def get_secondary_users(primary_user_id) do
    result =
      from(lu in __MODULE__,
        where: lu.primary_user_id == ^primary_user_id,
        preload: [:secondary_user]
      )
      |> Sanbase.Repo.all()
      |> Enum.map(& &1.secondary_user)

    {:ok, result}
  end

  def remove_linked_user_pair(primary_user_id, secondary_user_id) do
    {_num, nil} =
      from(lu in __MODULE__,
        where:
          lu.primary_user_id == ^primary_user_id and lu.secondary_user_id == ^secondary_user_id
      )
      |> Sanbase.Repo.delete_all()

    :ok
  end

  defp count_secondaries(primary_user_id) do
    from(lu in __MODULE__,
      where: lu.primary_user_id == ^primary_user_id,
      select: count(lu.secondary_user_id)
    )
    |> Sanbase.Repo.one()
  end

  defp create_link(primary_user_id, secondary_user_id) do
    case Sanbase.Repo.get_by(__MODULE__,
           primary_user_id: primary_user_id,
           secondary_user_id: secondary_user_id
         ) do
      %__MODULE__{} = linked_user ->
        {:ok, linked_user}

      nil ->
        %__MODULE__{}
        |> changeset(%{secondary_user_id: secondary_user_id, primary_user_id: primary_user_id})
        |> Sanbase.Repo.insert()
    end
  end
end
