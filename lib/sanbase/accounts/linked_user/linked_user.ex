defmodule Sanbase.Accounts.LinkedUser do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User

  @max_secondaries_count 2

  schema "linked_users" do
    belongs_to(:primary_user, User)
    belongs_to(:secondary_user, User)
  end

  def changeset(%__MODULE__{} = lu, attrs) do
    lu
    |> cast(attrs, [:secondary_user_id, :primary_user_id])
    |> validate_required([:secondary_user_id, :primary_user_id])
    |> unique_constraint(:secondary_user_id)
  end

  def create(primary_user_id, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:count_secondary_users, fn _repo, _changes ->
      {:ok, count_secondaries(primary_user_id)}
    end)
    |> Ecto.Multi.run(:add_linked_users, fn _repo, %{count_secondary_users: count} ->
      case count < @max_secondaries_count do
        true -> create_link(primary_user_id, user_id)
        false -> {:error, "The maximum number of linked secondary users has been reached."}
      end
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{add_linked_users: result}} -> {:ok, result}
      {:error, _failed_op, error, _changes} -> {:error, error}
    end
  end

  def delete(primary_user_id, secondary_user_id) do
    case Sanbase.Repo.get_by(__MODULE__,
           primary_user_id: primary_user_id,
           secondary_user_id: secondary_user_id
         ) do
      nil ->
        {:error, "Users are not linked"}

      %__MODULE__{} = luc ->
        Sanbase.Repo.delete(luc)
    end
  end

  def get_primary_user(secondary_user_id) do
    result =
      from(lu in __MODULE__,
        where: lu.secondary_user_id == ^secondary_user_id,
        preload: [:primary_user]
      )
      |> Sanbase.Repo.one()

    case result do
      nil -> {:error, "No linked user found for user_id: #{secondary_user_id}"}
      %__MODULE__{primary_user: primary_user} -> {:ok, primary_user}
    end
  end

  def get_primary_user_id(secondary_user_id) do
    result =
      from(lu in __MODULE__,
        where: lu.secondary_user_id == ^secondary_user_id,
        select: lu.primary_user_id
      )
      |> Sanbase.Repo.one()

    case result do
      nil -> {:error, "No linked user found for user_id: #{secondary_user_id}"}
      primary_user_id -> {:ok, primary_user_id}
    end
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
        # Creating is idempotent
        {:ok, linked_user}

      nil ->
        %__MODULE__{}
        |> changeset(%{secondary_user_id: secondary_user_id, primary_user_id: primary_user_id})
        |> Sanbase.Repo.insert()
    end
  end
end
