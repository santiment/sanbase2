defmodule Sanbase.Accounts.UserRole do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.User

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

  def create(user_id, role_id) do
    %__MODULE__{}
    |> changeset(%{user_id: user_id, role_id: role_id})
    |> Sanbase.Repo.insert()
  end
end
