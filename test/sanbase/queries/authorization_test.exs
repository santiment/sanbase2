defmodule Sanbase.Queries.AuthorizationTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Queries.Authorization

  describe "best_dynamic_repo_for_user/1" do
    test "returns FreeUser when user has no subscriptions" do
      user = insert(:user)
      assert Authorization.best_dynamic_repo_for_user(user.id) == Sanbase.ClickhouseRepo.FreeUser
    end

    test "returns SanbaseProUser for SANBASE PRO subscription" do
      user = insert(:user)
      insert(:subscription_pro_sanbase, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.SanbaseProUser
    end

    test "returns SanbaseMaxUser for SANBASE MAX subscription" do
      user = insert(:user)
      insert(:subscription_max_sanbase, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.SanbaseMaxUser
    end

    test "returns BusinessProUser for SANAPI BUSINESS_PRO subscription" do
      user = insert(:user)
      insert(:subscription_business_pro_monthly, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.BusinessProUser
    end

    test "returns BusinessMaxUser for SANAPI BUSINESS_MAX subscription" do
      user = insert(:user)
      insert(:subscription_business_max_monthly, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.BusinessMaxUser
    end

    test "picks the most permissive repo when user has SANBASE PRO + SANAPI BUSINESS_MAX" do
      user = insert(:user)
      insert(:subscription_pro_sanbase, user: user)
      insert(:subscription_business_max_monthly, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.BusinessMaxUser
    end

    test "picks the most permissive repo when user has SANBASE MAX + SANAPI BUSINESS_PRO" do
      user = insert(:user)
      insert(:subscription_max_sanbase, user: user)
      insert(:subscription_business_pro_monthly, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.BusinessProUser
    end

    test "picks the most permissive repo when user has SANBASE PRO_PLUS + SANAPI BUSINESS_PRO" do
      user = insert(:user)
      insert(:subscription_pro_plus_sanbase, user: user)
      insert(:subscription_business_pro_monthly, user: user)

      assert Authorization.best_dynamic_repo_for_user(user.id) ==
               Sanbase.ClickhouseRepo.BusinessProUser
    end
  end

  describe "user_can_execute_query/3" do
    test "Santiment employees can run queries even on the free plan" do
      # The users built by `insert(:user)` have @santiment.net emails and are
      # treated as Santiment employees, which bypass the subscription check.
      employee = insert(:user)
      assert Authorization.user_can_execute_query(employee, "SANBASE", "FREE") == :ok
    end

    test "free users without an active subscription cannot run queries" do
      user = insert(:user, email: "regular-user@example.com")

      assert {:error, error_msg} = Authorization.user_can_execute_query(user, "SANBASE", "FREE")
      assert error_msg =~ "Running queries requires an active subscription"
    end

    test "internal basic-auth requests (nil plan) can run queries" do
      user = insert(:user, email: "regular-user@example.com")
      assert Authorization.user_can_execute_query(user, nil, nil) == :ok
    end
  end
end
