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
end
