defmodule Sanbase.Auth.UserPermissionsTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Auth.User

  setup do
    Sanbase.Billing.TestSeed.seed_products_and_plans()
    %{user: insert(:user)}
  end

  test "user with subscriptions to some products", %{user: user} do
    insert(:subscription_pro, user: user)
    insert(:subscription_pro_sheets, user: user)

    assert User.Permissions.permissions(user) == %{
             api: true,
             sanbase: false,
             spreadsheet: true,
             sangraphs: false
           }
  end
end
