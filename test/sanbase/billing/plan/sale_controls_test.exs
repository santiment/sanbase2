defmodule Sanbase.Billing.Plan.SaleControlsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.SaleControls
  alias Sanbase.Repo

  setup context do
    for plan <- [
          context.plans.plan_business_pro_monthly,
          context.plans.plan_business_max_monthly
        ] do
      plan
      |> Plan.changeset(%{is_deprecated: false, is_private: false})
      |> Repo.update!()
    end

    bundle =
      case Plan.bundle_plan("month") do
        %Plan{} = plan ->
          plan
          |> Plan.changeset(%{is_private: true, is_deprecated: false})
          |> Repo.update!()

        nil ->
          Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9800")

          insert(:plan_pro,
            id: 9801,
            name: "BUNDLE",
            product_id: context.product_api.id,
            interval: "month",
            amount: 0,
            is_deprecated: false,
            is_private: true,
            stripe_id: "plan_bundle_m_" <> Ecto.UUID.generate()
          )
      end

    insert(:role_san_team)

    %{bundle: bundle}
  end

  test "bundle starts deactivated (private); business starts active", context do
    refute SaleControls.bundle_plans_active?()
    assert SaleControls.business_plans_active?()
    assert Repo.reload!(context.bundle).is_private
  end

  test "activate/deactivate bundle plans toggles is_private", context do
    assert {:ok, ids} = SaleControls.activate_bundle_plans()
    assert context.bundle.id in ids
    assert SaleControls.bundle_plans_active?()
    refute Repo.reload!(context.bundle).is_private

    assert {:ok, _} = SaleControls.deactivate_bundle_plans()
    refute SaleControls.bundle_plans_active?()
    assert Repo.reload!(context.bundle).is_private
  end

  test "activate/deactivate business plans moves both flags together", context do
    assert {:ok, _} = SaleControls.deactivate_business_plans()
    refute SaleControls.business_plans_active?()

    withdrawn = Repo.reload!(context.plans.plan_business_pro_monthly)
    assert withdrawn.is_deprecated
    assert withdrawn.is_private

    assert {:ok, _} = SaleControls.activate_business_plans()
    assert SaleControls.business_plans_active?()

    for_sale = Repo.reload!(context.plans.plan_business_pro_monthly)
    refute for_sale.is_deprecated
    refute for_sale.is_private
  end

  test "bundle_plans_visible? is false for regular users when deactivated" do
    user = insert(:user)
    refute SaleControls.bundle_plans_visible?(user)
  end

  test "bundle_plans_visible? is true for team when deactivated" do
    user = insert(:user)
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())
    assert SaleControls.bundle_plans_visible?(user)
  end

  test "bundle_plans_visible? is true for everyone when activated" do
    user = insert(:user)
    assert {:ok, _} = SaleControls.activate_bundle_plans()
    assert SaleControls.bundle_plans_visible?(user)
  end

  test "product_with_plans hides deprecated business plans after deactivate" do
    assert {:ok, _} = SaleControls.deactivate_business_plans()

    plan_names = listed_plan_names()

    refute "BUSINESS_PRO" in plan_names
    refute "BUSINESS_MAX" in plan_names
  end

  test "product_with_plans lists business plans again after activate" do
    assert {:ok, _} = SaleControls.deactivate_business_plans()
    assert {:ok, _} = SaleControls.activate_business_plans()

    plan_names = listed_plan_names()

    assert "BUSINESS_PRO" in plan_names
    assert "BUSINESS_MAX" in plan_names
  end

  # The sale controls must not reach any further than the two names they manage.
  # On production `FREE` on both products and the current Sanbase tiers are all
  # `is_private = true`, and several plans people still hold are deprecated -
  # filtering on either field in general empties most of the pricing page.
  test "product_with_plans keeps private plans and deprecated non-business plans", context do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9850")

    insert(:plan_pro,
      id: 9851,
      name: "PRIVATELY_SOLD",
      product_id: context.product_api.id,
      interval: "month",
      is_private: true,
      is_deprecated: false,
      stripe_id: "plan_private_" <> Ecto.UUID.generate()
    )

    insert(:plan_pro,
      id: 9852,
      name: "GRANDFATHERED",
      product_id: context.product_api.id,
      interval: "month",
      is_private: false,
      is_deprecated: true,
      stripe_id: "plan_grandfathered_" <> Ecto.UUID.generate()
    )

    plan_names = listed_plan_names()

    assert "PRIVATELY_SOLD" in plan_names
    assert "GRANDFATHERED" in plan_names
  end

  test "product_with_plans never lists the BUNDLE marker plans" do
    assert {:ok, _} = SaleControls.activate_bundle_plans()

    refute "BUNDLE" in listed_plan_names()
  end

  defp listed_plan_names do
    assert {:ok, products} = Plan.product_with_plans()

    products
    |> Enum.flat_map(& &1.plans)
    |> Enum.map(& &1.name)
  end
end
