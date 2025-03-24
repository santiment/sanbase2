defmodule Sanbase.Accounts.Role do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @san_team_role_id 1
  @san_family_role_id 2
  @san_moderator_role_id 3
  # Comment them out
  # @registry_viewer_role_id 4
  # @registry_change_suggester_id 5
  # @registry_change_approver_role_id 6
  # @registry_deployer_role_id 7
  # @registry_owner_id 8
  # @admin_panel_viewer_id 9
  # @admin_panel_editor_id 10
  # @admin_panel_owner_id 11

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

  def by_names(names) do
    from(
      r in __MODULE__,
      where: r.name in ^names
    )
    |> Sanbase.Repo.all()
  end

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
