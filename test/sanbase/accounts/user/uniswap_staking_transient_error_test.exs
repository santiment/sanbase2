defmodule Sanbase.Accounts.User.UniswapStakingTransientErrorTest do
  @moduledoc ~s"""
  Reproduces SANBASE-BACKEND-PROD-GBD:
  UniswapStaking.UpdateError: Failed to fetch Uniswap SAN staked balances, update aborted:
  {:invalid_json, %Jason.DecodeError{data: "<html>...502 Bad Gateway...cloudflare..."}}

  The update runs every 30 minutes. A single transient 502 from the Cloudflare
  fronted RPC node aborts the whole run and is reported to Sentry immediately.
  A transient RPC failure should be retried before giving up, and only reported
  when it persists.
  """
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.User.UniswapStaking
  alias Sanbase.SmartContracts.UniswapPair

  @bad_gateway_error {:error,
                      {:invalid_json,
                       %Jason.DecodeError{
                         position: 0,
                         token: nil,
                         data:
                           "<html>\r\n<head><title>502 Bad Gateway</title></head>\r\n<body>\r\n" <>
                             "<center><h1>502 Bad Gateway</h1></center>\r\n<hr><center>cloudflare" <>
                             "</center>\r\n</body>\r\n</html>\r\n"
                       }}}

  setup do
    user = insert(:user)
    {:ok, _} = EthAccount.create(user.id, "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9")
    %{user: user}
  end

  test "a single transient 502 from the RPC node is retried and not reported", %{user: user} do
    test_pid = self()

    # The first balances_of call fails with the 502 HTML body, all later ones succeed
    calls = :counters.new(1, [])

    balances_of = fn _addresses, _contract ->
      :counters.add(calls, 1, 1)

      case :counters.get(calls, 1) do
        1 -> @bad_gateway_error
        _ -> {:ok, [2.0]}
      end
    end

    Sanbase.Mock.prepare_mock(UniswapPair, :balances_of, balances_of)
    |> Sanbase.Mock.prepare_mock2(&UniswapPair.total_supply/1, 10.0)
    |> Sanbase.Mock.prepare_mock2(&UniswapPair.reserves/1, {5.0, 3.0})
    |> Sanbase.Mock.prepare_mock2(&UniswapPair.get_san_position/1, 0)
    |> Sanbase.Mock.prepare_mock(Sentry, :capture_exception, fn exception, _opts ->
      send(test_pid, {:sentry_exception, exception})
      {:ok, "mocked"}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      capture_log(fn ->
        assert {:ok, {1, _}} = UniswapStaking.update_all_uniswap_san_staked_users()
      end)

      assert [%UniswapStaking{user_id: user_id}] =
               UniswapStaking.fetch_all_uniswap_staked_users()

      assert user_id == user.id
      refute_received {:sentry_exception, _}
    end)
  end
end
