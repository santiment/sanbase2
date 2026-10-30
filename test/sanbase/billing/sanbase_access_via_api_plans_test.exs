defmodule Sanbase.Billing.SanbaseAccessViaApiPlansTest do
  @moduledoc ~s"""
  SanAPI Business, Institutional and Enterprise plans include Sanbase PRO or
  higher. Users who have only such a plan get the Sanbase PRO features.
  """
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Billing
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription

  setup do
    institutional_plan = insert_api_plan(9700, "INSTITUTIONAL")
    enterprise_plan = insert_api_plan(9701, "ENTERPRISE")

    users_with_sanbase = %{
      "BUSINESS_PRO" => user_with(:subscription_business_pro_monthly),
      "BUSINESS_MAX" => user_with(:subscription_business_max_monthly),
      "INSTITUTIONAL" => user_with(:subscription_pro, plan_id: institutional_plan.id),
      "ENTERPRISE" => user_with(:subscription_pro, plan_id: enterprise_plan.id),
      "SANBASE PRO" => user_with(:subscription_pro_sanbase)
    }

    users_without_sanbase = %{
      "FREE" => insert(:user),
      "SANAPI PRO" => user_with(:subscription_pro),
      "SANBASE BASIC" => user_with(:subscription_basic_sanbase)
    }

    %{users_with_sanbase: users_with_sanbase, users_without_sanbase: users_without_sanbase}
  end

  test "user_has_sanbase_pro_access?/1", context do
    for {plan, user} <- context.users_with_sanbase do
      assert Subscription.user_has_sanbase_pro_access?(user.id), plan
    end

    for {plan, user} <- context.users_without_sanbase do
      refute Subscription.user_has_sanbase_pro_access?(user.id), plan
    end
  end

  test "sanbase_pro_access_from_auth?/1", context do
    for {plan, user} <- context.users_with_sanbase do
      assert Billing.sanbase_pro_access_from_auth?(%{current_user: user}), plan
    end

    for {plan, user} <- context.users_without_sanbase do
      refute Billing.sanbase_pro_access_from_auth?(%{current_user: user}), plan
    end
  end

  test "get_sanbase_pro_user_ids/0 includes the users whose SanAPI plan includes Sanbase",
       context do
    {:ok, user_ids} = Billing.get_sanbase_pro_user_ids()

    for {plan, user} <- context.users_with_sanbase do
      assert user.id in user_ids, plan
    end

    for {plan, user} <- Map.delete(context.users_without_sanbase, "SANBASE BASIC") do
      refute user.id in user_ids, plan
    end
  end

  defp insert_api_plan(id, name) do
    insert(:plan_pro,
      id: id,
      name: name,
      product_id: Product.product_api(),
      stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
    )
  end

  defp user_with(subscription_factory, attrs \\ []) do
    user = insert(:user)
    insert(subscription_factory, Keyword.put(attrs, :user, user))
    user
  end
end
