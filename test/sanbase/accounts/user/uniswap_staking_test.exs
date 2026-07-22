defmodule Sanbase.Accounts.User.UniswapStakingTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Accounts.User.UniswapStaking
  alias Sanbase.Repo
  alias Sanbase.SmartContracts.UniswapPair

  setup do
    user = insert(:user)
    address = "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
    {:ok, _} = EthAccount.create(user.id, address)

    %{user: user, address: address}
  end

  describe "update_all_uniswap_san_staked_users/0" do
    test "stores the staked amount when all contract calls succeed", %{user: user} do
      Sanbase.Mock.prepare_mock2(&UniswapPair.balances_of/2, {:ok, [2.0]})
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.total_supply/1, 10.0)
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.reserves/1, {5.0, 3.0})
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.get_san_position/1, 0)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, {1, _}} = UniswapStaking.update_all_uniswap_san_staked_users()

        assert [%UniswapStaking{user_id: user_id, san_staked: san_staked}] =
                 UniswapStaking.fetch_all_uniswap_staked_users()

        assert user_id == user.id
        # 2 pair contracts, each contributing 2.0 / 10.0 * 5.0 = 1.0
        assert san_staked == 2.0
      end)
    end

    test "does not wipe existing data when a contract metadata call fails", %{user: user} do
      %UniswapStaking{}
      |> UniswapStaking.changeset(%{san_staked: 5.0})
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert!()

      error = {:error, %Mint.TransportError{reason: :nxdomain}}

      Sanbase.Mock.prepare_mock2(&UniswapPair.balances_of/2, {:ok, [2.0]})
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.total_supply/1, error)
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.reserves/1, {5.0, 3.0})
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.get_san_position/1, 0)
      |> prepare_sentry_exception_mock(self())
      |> Sanbase.Mock.run_with_mocks(fn ->
        capture_log(fn ->
          assert {:error, %Mint.TransportError{reason: :nxdomain}} =
                   UniswapStaking.update_all_uniswap_san_staked_users()
        end)

        assert [%UniswapStaking{san_staked: 5.0}] =
                 UniswapStaking.fetch_all_uniswap_staked_users()

        assert_receive {:sentry_exception, %UniswapStaking.UpdateError{message: message}}
        assert message =~ ":nxdomain"
      end)
    end

    test "does not wipe existing data when the RPC node is unreachable", %{user: user} do
      %UniswapStaking{}
      |> UniswapStaking.changeset(%{san_staked: 5.0})
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert!()

      error = {:error, %Mint.TransportError{reason: :nxdomain}}

      Sanbase.Mock.prepare_mock2(&UniswapPair.balances_of/2, error)
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.total_supply/1, 10.0)
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.reserves/1, {5.0, 3.0})
      |> Sanbase.Mock.prepare_mock2(&UniswapPair.get_san_position/1, 0)
      |> prepare_sentry_exception_mock(self())
      |> Sanbase.Mock.run_with_mocks(fn ->
        capture_log(fn ->
          assert {:error, %Mint.TransportError{reason: :nxdomain}} =
                   UniswapStaking.update_all_uniswap_san_staked_users()
        end)

        assert [%UniswapStaking{san_staked: 5.0}] =
                 UniswapStaking.fetch_all_uniswap_staked_users()

        assert_receive {:sentry_exception, %UniswapStaking.UpdateError{message: message}}
        assert message =~ ":nxdomain"
      end)
    end
  end

  defp prepare_sentry_exception_mock(mock_state, test_pid) do
    Sanbase.Mock.prepare_mock(mock_state, Sentry, :capture_exception, fn exception, _opts ->
      send(test_pid, {:sentry_exception, exception})
      {:ok, "mocked"}
    end)
  end

  describe "UniswapPair.balances_of/2" do
    setup do
      %{
        addresses: [
          "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9",
          "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
        ],
        contract: UniswapPair.san_eth_pair_contract()
      }
    end

    test "returns the balances on success", %{addresses: addresses, contract: contract} do
      batch_result = [[1_000_000_000_000_000_000], [2_500_000_000_000_000_000]]

      Sanbase.Mock.prepare_mock2(
        &Sanbase.SmartContracts.Utils.call_contract_batch/5,
        batch_result
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, [1.0, 2.5]} = UniswapPair.balances_of(addresses, contract)
      end)
    end

    test "returns the error when the whole batch request fails", %{
      addresses: addresses,
      contract: contract
    } do
      error = {:error, %Mint.TransportError{reason: :nxdomain}}

      Sanbase.Mock.prepare_mock2(&Sanbase.SmartContracts.Utils.call_contract_batch/5, error)
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert ^error = UniswapPair.balances_of(addresses, contract)
      end)
    end

    test "returns the error when a single request in the batch fails", %{
      addresses: addresses,
      contract: contract
    } do
      batch_result = [[1_000_000_000_000_000_000], {:error, :empty_response}]

      Sanbase.Mock.prepare_mock2(
        &Sanbase.SmartContracts.Utils.call_contract_batch/5,
        batch_result
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:error, :empty_response} = UniswapPair.balances_of(addresses, contract)
      end)
    end
  end
end
