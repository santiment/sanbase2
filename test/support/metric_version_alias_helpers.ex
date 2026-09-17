defmodule Sanbase.MetricVersionAliasHelpers do
  @moduledoc """
  Fixtures shared by the metric version alias tests.
  """

  alias Sanbase.Metric.VersionAlias

  @doc "Insert an alias row through the changeset and drop the alias cache."
  def create_alias!(attrs) do
    {:ok, row} = %VersionAlias{} |> VersionAlias.changeset(attrs) |> Sanbase.Repo.insert()
    VersionAlias.clear_cache()
    row
  end

  @doc "A conn signed in as an admin panel owner, for the generic admin routes."
  def admin_owner_conn() do
    user = Sanbase.Factory.insert(:user)
    role = Sanbase.Factory.insert(:role_admin_panel_owner)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), jwt_tokens)
  end
end
