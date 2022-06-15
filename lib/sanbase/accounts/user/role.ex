defmodule Sanbase.Accounts.Role do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @san_team_role_id 1
  @san_family_role_id 2
  @san_moderator_role_id 3

  schema "roles" do
    field(:name, :string)
  end

  def changeset(%__MODULE__{} = role, attrs \\ %{}) do
    role
    |> cast(attrs, [:name])
  end

  def san_team_role_id(), do: @san_team_role_id
  def san_family_role_id(), do: @san_family_role_id
  def san_moderator_role_id(), do: @san_moderator_role_id

  def san_family_ids(), do: get_role_ids(@san_family_role_id)
  def san_team_ids(), do: get_role_ids(@san_team_role_id)
  def san_moderator_ids(), do: get_role_ids(@san_moderator_role_id)

  # Private functions

  defp get_role_ids(role_id) do
    from(
      ur in Sanbase.Accounts.UserRole,
      where: ur.role_id == ^role_id,
      select: ur.user_id
    )
    |> Sanbase.Repo.all()
  end
end
