defmodule Sanbase.Billing.Plan.SaleControls do
  @moduledoc ~s"""
  Admin toggles for which SanAPI plans are for sale.

  * **Bundle / new plans** (`BUNDLE*`, `INSTITUTIONAL*`, `ENTERPRISE*`) —
    `is_private` false = active (self-serve), true = deactivated (staff can still
    preview via team role). One switch covers the whole offering; there is no state
    in which packages are for sale and Institutional or Enterprise are not.
  * **Business plans** (`BUSINESS_PRO`, `BUSINESS_MAX`) — `is_deprecated` false =
    active for sale, true = withdrawn from sale. Existing subscribers keep access
    either way.

  ## Why the Business plans do not touch `is_private`

  `is_deprecated` is the only one of the two that decides anything. It is what
  `Sanbase.Billing.Plan.product_with_plans/0` filters those names on, and it is
  the only field the web app asks for - its plans query selects
  `id name interval amount isDeprecated`, and `isPrivate` appears nowhere in
  `san-webkit` or `sanbase-app`. The Business rows are `is_private = true` on
  production while being sold on the pricing page every day, which is the same
  point from the other direction: nothing reads it.

  So writing it here would change production data on a button press with no
  effect anyone can observe.
  """

  import Ecto.Query

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Product
  alias Sanbase.Repo

  @spec business_plan_names() :: [String.t()]
  def business_plan_names, do: Plan.business_plan_names()

  @doc ~s"""
  Whether the user is a Santiment team member.

  Asked once per request on the bundle catalog and on every subscribe, so it is a
  single scoped `exists?` rather than reading every row of `user_roles` and
  searching the result in memory.
  """
  @spec team_member?(User.t() | nil) :: boolean()
  def team_member?(%User{id: user_id}) when is_integer(user_id) do
    from(ur in UserRole,
      where: ur.user_id == ^user_id and ur.role_id == ^Role.san_team_role_id()
    )
    |> Repo.exists?()
  end

  def team_member?(_), do: false

  @doc ~s"""
  Bundle catalog and mutations are available when new plans are activated, or
  always for Santiment team members (preview while deactivated).
  """
  @spec bundle_plans_visible?(User.t() | nil) :: boolean()
  def bundle_plans_visible?(user) do
    bundle_plans_active?() or team_member?(user)
  end

  @spec bundle_plans_active?() :: boolean()
  def bundle_plans_active? do
    product_api = Product.product_api()

    from(p in Plan,
      where: p.product_id == ^product_api,
      where:
        like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%") or like(p.name, "ENTERPRISE%"),
      where: p.is_private == false,
      select: count(p.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @spec business_plans_active?() :: boolean()
  def business_plans_active? do
    product_api = Product.product_api()

    from(p in Plan,
      where: p.product_id == ^product_api and p.name in ^business_plan_names(),
      where: coalesce(p.is_deprecated, false) == false,
      select: count(p.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @spec status() :: %{
          bundle_plans_active?: boolean(),
          business_plans_active?: boolean(),
          bundle_plan_ids: [integer()],
          business_plan_ids: [integer()]
        }
  def status do
    %{
      bundle_plans_active?: bundle_plans_active?(),
      business_plans_active?: business_plans_active?(),
      bundle_plan_ids: Enum.map(list_new_offering_plans(), & &1.id),
      business_plan_ids: Enum.map(list_business_plans(), & &1.id)
    }
  end

  @spec activate_bundle_plans() :: {:ok, [integer()]} | {:error, term()}
  def activate_bundle_plans, do: set_new_offering_private(false)

  @spec deactivate_bundle_plans() :: {:ok, [integer()]} | {:error, term()}
  def deactivate_bundle_plans, do: set_new_offering_private(true)

  @spec activate_business_plans() :: {:ok, [integer()]} | {:error, term()}
  def activate_business_plans, do: set_business_for_sale(true)

  @spec deactivate_business_plans() :: {:ok, [integer()]} | {:error, term()}
  def deactivate_business_plans, do: set_business_for_sale(false)

  defp set_new_offering_private(private?) do
    product_api = Product.product_api()

    ids =
      from(p in Plan,
        where: p.product_id == ^product_api,
        where:
          like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%") or like(p.name, "ENTERPRISE%"),
        select: p.id
      )
      |> Repo.all()

    if ids != [] do
      from(p in Plan, where: p.id in ^ids)
      |> Repo.update_all(set: [is_private: private?])
    end

    {:ok, ids}
  end

  defp set_business_for_sale(for_sale?) do
    product_api = Product.product_api()

    ids =
      from(p in Plan,
        where: p.product_id == ^product_api and p.name in ^business_plan_names(),
        select: p.id
      )
      |> Repo.all()

    if ids != [] do
      from(p in Plan, where: p.id in ^ids)
      |> Repo.update_all(set: [is_deprecated: not for_sale?])
    end

    {:ok, ids}
  end

  defp list_new_offering_plans do
    product_api = Product.product_api()

    from(p in Plan,
      where: p.product_id == ^product_api,
      where:
        like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%") or like(p.name, "ENTERPRISE%"),
      order_by: [asc: p.name, asc: p.interval]
    )
    |> Repo.all()
  end

  defp list_business_plans do
    product_api = Product.product_api()

    from(p in Plan,
      where: p.product_id == ^product_api and p.name in ^business_plan_names(),
      order_by: [asc: p.name, asc: p.interval]
    )
    |> Repo.all()
  end
end
