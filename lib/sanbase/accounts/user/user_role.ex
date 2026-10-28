defmodule Sanbase.Accounts.UserRole do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Accounts.{User, Role}

  @primary_key false
  schema "user_roles" do
    belongs_to(:user, User, primary_key: true)
    belongs_to(:role, Role, primary_key: true)
    timestamps()
  end

  def changeset(%__MODULE__{} = user_role, attrs \\ %{}) do
    user_role
    |> cast(attrs, [:user_id, :role_id])
    |> unique_constraint(:user, name: :user_roles_user_id_role_id_index)
  end

  @doc """
  Grants a role. Deliberately unauthorized — also the IEx bootstrap path, and the
  first Admin Panel Owner must be creatable when no Owner exists. Web-reachable
  callers check the acting user themselves, as `UserRolesLive` does.
  """
  def create(user_id, role_id) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, role_id: role_id})
    |> Sanbase.Repo.insert()
  end

  def delete(user_id, role_id) do
    import Ecto.Query

    from(ur in __MODULE__,
      where: ur.user_id == ^user_id and ur.role_id == ^role_id
    )
    |> Sanbase.Repo.delete_all()
  end

  @doc """
  Grants `grant_role_ids` and revokes `revoke_role_ids` in one transaction.
  Unauthorized, like `create/2`.
  """
  def update_roles(user_id, grant_role_ids, revoke_role_ids) do
    import Ecto.Query

    revoke_query =
      from(ur in __MODULE__, where: ur.user_id == ^user_id and ur.role_id in ^revoke_role_ids)

    grant_role_ids
    |> Enum.reduce(Ecto.Multi.new(), fn role_id, multi ->
      Ecto.Multi.insert(
        multi,
        {:grant, role_id},
        changeset(%__MODULE__{}, %{user_id: user_id, role_id: role_id})
      )
    end)
    |> Ecto.Multi.delete_all(:revoke, revoke_query)
    |> Sanbase.Repo.transaction()
  end
end
