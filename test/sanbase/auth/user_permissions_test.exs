defmodule Sanbase.Auth.UserPermissionsTest do
  use Sanbase.DataCase, async: false

  import Mockery
  import Sanbase.Factory

  alias Sanbase.Auth.{User, EthAccount}

  setup do
    %{user: insert(:user)}
  end

  test "user with subscriptions to some products", context do
    insert(:subscription_pro, user: context.user)
    insert(:subscription_pro_sheets, user: context.user)

    assert User.permissions(context.user) == %{
             api: true,
             sanbase: false,
             spreadsheet: true,
             sangraphs: false
           }
  end
end
