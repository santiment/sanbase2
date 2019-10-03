defmodule Sanbase.Auth.Role do
  use Ecto.Schema

  import Ecto.Changeset

  @san_team_role_id 1
  @san_family_role_id 2

  schema "roles" do
    field(:name, :string)

    has_many(:users, {"user_roles", Sanbase.Auth.UserRole}, on_delete: :delete_all)
  end

  def changeset(%__MODULE__{} = role, attrs \\ %{}) do
    role
    |> cast(attrs, [:name])
  end

  def san_team_role_id(), do: @san_team_role_id
  def san_family_role_id(), do: @san_family_role_id
end
