defmodule Sanbase.Accounts.User.UniswapStakingTransientErrorTest do
  # A 502 HTML page from the RPC node aborted the update
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

  for {name, error} <- [
        {"a 502 HTML page", Macro.escape(@bad_gateway_error)},
        {"a transport error", Macro.escape({:error, %Mint.TransportError{reason: :closed}})},
        {"an HTTP error",
         Macro.escape({:error, %Mint.HTTPError{module: Mint.HTTP1, reason: :invalid_status_line}})},
        {"a Finch error", Macro.escape({:error, %Finch.Error{reason: :request_timeout}})}
      ] do
    test "a single transient error (#{name}) is retried and not reported", %{user: user} do
      test_pid = self()
      error = unquote(error)

      balances_of =
        [fn -> error end, fn -> {:ok, [2.0]} end, fn -> {:ok, [2.0]} end]
        |> Sanbase.Mock.wrap_consecutives(arity: 2, cycle?: false)

      mocks(balances_of, test_pid)
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

  test "a non-transient error is not retried and is reported" do
    test_pid = self()

    balances_of = fn _addresses, _contract ->
      send(test_pid, :balances_of_called)
      {:error, :contract_reverted}
    end

    mocks(balances_of, test_pid)
    |> Sanbase.Mock.run_with_mocks(fn ->
      capture_log(fn ->
        assert {:error, :contract_reverted} =
                 UniswapStaking.update_all_uniswap_san_staked_users()
      end)

      assert_received :balances_of_called
      refute_received :balances_of_called
      assert_received {:sentry_exception, _}
    end)
  end

  defp mocks(balances_of, test_pid) do
    Sanbase.Mock.prepare_mock(UniswapPair, :balances_of, balances_of)
    |> Sanbase.Mock.prepare_mock2(&UniswapPair.total_supply/1, 10.0)
    |> Sanbase.Mock.prepare_mock2(&UniswapPair.reserves/1, {5.0, 3.0})
    |> Sanbase.Mock.prepare_mock2(&UniswapPair.get_san_position/1, 0)
    |> Sanbase.Mock.prepare_mock(Sentry, :capture_exception, fn exception, _opts ->
      send(test_pid, {:sentry_exception, exception})
      {:ok, "mocked"}
    end)
  end
end
