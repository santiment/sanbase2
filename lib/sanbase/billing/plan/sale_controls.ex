defmodule Sanbase.Billing.Plan.SaleControls do
  @moduledoc ~s"""
  Admin toggles for which SanAPI plans are for sale.

  * **Bundle / new plans** (`BUNDLE*`, `INSTITUTIONAL*`) — `is_private` false = active
    (self-serve), true = deactivated (staff can still preview via team role).
  * **Business plans** (`BUSINESS_PRO`, `BUSINESS_MAX`) — active for sale means
    `is_deprecated` false *and* `is_private` false; withdrawn sets both true.
    Existing subscribers keep access either way.

  ## Why the Business plans move both flags

  `Sanbase.Billing.Plan.product_with_plans/0` filters those two names on
  `is_deprecated`, so that is what makes them appear on the pricing page. But
  both flags are exposed on the GraphQL plan type and a client may well hide
  anything `isPrivate`, and the Business rows are `is_private = true` on
  production today. Moving one flag without the other leaves a plan that is for
  sale by one reading and not by the other, which is exactly the state this
  module exists to remove.
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
      where: like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%"),
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
        where: like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%"),
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
      |> Repo.update_all(set: [is_deprecated: not for_sale?, is_private: not for_sale?])
    end

    {:ok, ids}
  end

  defp list_new_offering_plans do
    product_api = Product.product_api()

    from(p in Plan,
      where: p.product_id == ^product_api,
      where: like(p.name, "BUNDLE%") or like(p.name, "INSTITUTIONAL%"),
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
