defmodule Sanbase.Auth.UserPermissionsTest do
  use Sanbase.DataCase, async: false

  import Mockery
  import Sanbase.Factory

  alias Sanbase.Auth.{User, EthAccount}

  test "user with 0 san tokens has no permissions" do
    user =
      insert(:user,
        san_balance: 0,
        san_balance_updated_at: Timex.now(),
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        privacy_policy_accepted: true
      )

    assert User.permissions(user) ==
             {:ok, %{historical_data: false, realtime_data: false, spreadsheet: false}}
  end

  test "user with 1000 san tokens has all permissions" do
    user =
      insert(:user,
        san_balance: 1000,
        san_balance_updated_at: Timex.now(),
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        privacy_policy_accepted: true
      )

    assert User.permissions(user) ==
             {:ok, %{historical_data: true, realtime_data: true, spreadsheet: true}}
  end

  test "enough san tokens when san_balance updated when being stale" do
    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:ok, Decimal.new(1200)})

    user =
      insert(:user,
        san_balance: 0,
        san_balance_updated_at: Timex.shift(Timex.now(), days: -2),
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        privacy_policy_accepted: true
      )

    assert User.permissions(user) ==
             {:ok, %{historical_data: true, realtime_data: true, spreadsheet: true}}
  end

  test "not enough san tokens when san_balance updated when being stale" do
    mock(Sanbase.InternalServices.Ethauth, :san_balance, {:ok, Decimal.new(100)})

    user =
      insert(:user,
        san_balance: 0,
        san_balance_updated_at: Timex.shift(Timex.now(), days: -2),
        eth_accounts: [%EthAccount{address: "0x000000000001"}],
        privacy_policy_accepted: true
      )

    assert User.permissions(user) ==
             {:ok, %{historical_data: false, realtime_data: false, spreadsheet: false}}
  end
end
