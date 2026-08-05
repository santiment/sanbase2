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

  test "activate/deactivate business plans toggles is_deprecated", context do
    assert {:ok, _} = SaleControls.deactivate_business_plans()
    refute SaleControls.business_plans_active?()
    assert Repo.reload!(context.plans.plan_business_pro_monthly).is_deprecated

    assert {:ok, _} = SaleControls.activate_business_plans()
    assert SaleControls.business_plans_active?()
    refute Repo.reload!(context.plans.plan_business_pro_monthly).is_deprecated
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
    assert {:ok, products} = Plan.product_with_plans()

    plan_names =
      products
      |> Enum.flat_map(& &1.plans)
      |> Enum.map(& &1.name)

    refute "BUSINESS_PRO" in plan_names
    refute "BUSINESS_MAX" in plan_names
  end
end
