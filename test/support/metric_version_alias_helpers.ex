defmodule Sanbase.MetricVersionAliasHelpers do
  @moduledoc "Fixtures shared by the metric version alias tests."

  import Ecto.Query, only: [from: 2]

  alias Sanbase.Metric.VersionAlias
  alias Sanbase.Metric.VersionPlanAccess

  # The plan access the migration seeds, by kind of version.
  @everyone [%{product: "SANAPI", plan: "ANY"}, %{product: "SANBASE", plan: "ANY"}]
  @sanbase [%{product: "SANBASE", plan: "ANY"}]
  @business [
    %{product: "SANAPI", plan: "BUSINESS_PRO"},
    %{product: "SANAPI", plan: "BUSINESS_MAX"}
  ]
  @pit [
    %{
      product: "SANAPI",
      plan: "BUSINESS_MAX",
      billing_interval: "year",
      accessible_if_trial: false
    }
  ]

  def everyone(), do: @everyone
  def business(), do: @business ++ @sanbase
  def pit(), do: @pit ++ @sanbase

  @doc "Insert an alias row. `:plan_access` is a list of plan access attrs to add to it."
  @spec create_alias!(map()) :: VersionAlias.t()
  def create_alias!(attrs) do
    {plan_access, attrs} = Map.pop(attrs, :plan_access, [])
    {:ok, row} = %VersionAlias{} |> VersionAlias.changeset(attrs) |> Sanbase.Repo.insert()
    grant!(row, plan_access)
  end

  @doc """
  The alias row of the scope and version, created from `attrs` when missing, with the
  `:plan_access` added. A migrated test database already has the seeded rows, one
  loaded from structure.sql does not.
  """
  @spec ensure_alias!(map()) :: VersionAlias.t()
  def ensure_alias!(attrs) do
    scope = Map.get(attrs, :scope, "global")
    num = Map.fetch!(attrs, :version_num)

    case Sanbase.Repo.one(
           from(a in VersionAlias, where: a.scope == ^scope and a.version_num == ^num)
         ) do
      nil -> create_alias!(attrs)
      row -> grant!(row, Map.get(attrs, :plan_access, []))
    end
  end

  @doc "Add plan access to an alias row. Rows that already exist are kept."
  @spec grant!(VersionAlias.t(), [map()]) :: VersionAlias.t()
  def grant!(%VersionAlias{} = row, plan_access) do
    for attrs <- plan_access do
      {:ok, _} =
        %VersionPlanAccess{}
        |> VersionPlanAccess.changeset(Map.put(attrs, :version_alias_id, row.id))
        |> Sanbase.Repo.insert(on_conflict: :nothing)
    end

    VersionAlias.clear_cache()
    row
  end

  @doc "The aliases and plan access the migrations seed, in the given scope."
  @spec ensure_seeded_versions!(String.t()) :: :ok
  def ensure_seeded_versions!(scope \\ "global") do
    for {num, name, plan_access} <- [
          {"1.0", "original:v1", @everyone},
          {"2.0", "modern:v1", business()},
          {"2.1", "modern_pit:v1", pit()},
          {"2.1.1", "modern_pit:v1.1", pit()},
          {"2.1.2", "modern_pit:v1.2", pit()},
          {"3.0", "stock:v1", business()},
          {"3.1", "stock_pit:v1", pit()}
        ] do
      ensure_alias!(%{
        scope: scope,
        version_num: num,
        version_name: name,
        plan_access: plan_access
      })
    end

    :ok
  end

  @doc "A conn logged in as a user with the admin panel role from the factory."
  @spec admin_conn(atom()) :: Plug.Conn.t()
  def admin_conn(role_factory) do
    user = Sanbase.Factory.insert(:user)
    role = Sanbase.Factory.insert(role_factory)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), jwt_tokens)
  end
end
