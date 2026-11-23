defmodule Sanbase.Billing.Subscription.SanbaseNFTTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.SanbaseNFT
  alias Sanbase.SmartContracts.Utils

  @valid_address "0x9024d48cc7be15343dfd76ef051fa5264cfbf7a9"
  @other_valid_address "0x23918e95d234eec054566dde0841d69311814495"

  test "an invalid stored address is skipped instead of failing the whole run" do
    {:ok, _} = EthAccount.create(insert(:user).id, @valid_address)
    {:ok, _} = EthAccount.create(insert(:user).id, @valid_address <> "_invalid")

    test_pid = self()

    Sanbase.Mock.prepare_mock(Utils, :call_contract_batch, fn _contract,
                                                              _abi,
                                                              args,
                                                              _ret,
                                                              _opts ->
      send(test_pid, {:balance_of_args, args})
      Enum.map(args, fn _ -> [0] end)
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert :ok = SanbaseNFT.maybe_create()

      assert_received {:balance_of_args, [[address]]}
      assert Utils.encode_address(address) == @valid_address
    end)
  end

  describe "a user with a valid NFT and an invalid stored address" do
    setup do
      user = insert(:user)
      {:ok, _} = EthAccount.create(user.id, @valid_address)
      {:ok, _} = EthAccount.create(user.id, @other_valid_address <> "_invalid")
      %{user: user}
    end

    test "maybe_create/0 creates the subscription", %{user: user} do
      nft_contract_mocks()
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert :ok = SanbaseNFT.maybe_create()

        assert [%Subscription{user_id: user_id}] =
                 Subscription.NFTSubscription.list_nft_subscriptions(:burning_nft)

        assert user_id == user.id
      end)
    end

    test "maybe_remove/0 keeps the subscription", %{user: user} do
      Subscription.NFTSubscription.create_nft_subscription(
        user.id,
        :burning_nft,
        Timex.shift(Timex.now(), days: 30)
      )

      nft_contract_mocks()
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert :ok = SanbaseNFT.maybe_remove()

        assert [%Subscription{user_id: user_id}] =
                 Subscription.NFTSubscription.list_nft_subscriptions(:burning_nft)

        assert user_id == user.id
      end)
    end
  end

  # One valid NFT token for every address
  defp nft_contract_mocks() do
    Sanbase.Mock.prepare_mock(Utils, :call_contract_batch, fn _contract,
                                                              _abi,
                                                              args,
                                                              _ret,
                                                              _opts ->
      Enum.map(args, fn _ -> [1] end)
    end)
    |> Sanbase.Mock.prepare_mock(Utils, :call_contract, fn _contract, abi, _args, _ret ->
      case abi.function do
        "balanceOf" -> [1]
        "tokenOfOwnerByIndex" -> [1]
        "isValid" -> [true]
      end
    end)
  end
end
