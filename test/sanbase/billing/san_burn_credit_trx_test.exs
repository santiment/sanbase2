defmodule Sanbase.Billing.SanBurnCreditTransactionTest do
  use Sanbase.DataCase, async: false
  import Sanbase.Factory

  alias Sanbase.Billing.Subscription.SanBurnCreditTransaction
  alias Sanbase.Accounts.EthAccount

  test "1" do
    user =
      insert(:user,
        eth_accounts: [%EthAccount{address: "0x1"}],
        stripe_customer_id: "s1"
      )

    timestamp = ~U[2022-05-23 05:43:40Z] |> DateTime.to_unix()
    rows = [[timestamp, "0x1", 1000, "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"]]

    data = %{price_usd: 4, price_btc: 0.03, marketcap: 100, volume: 100}

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.last_record_before/2, {:ok, data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.StripeApi.add_credit/3, {:ok, %{}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()
      [burn_trx] = SanBurnCreditTransaction.all()

      result =
        Map.from_struct(burn_trx)
        |> Map.take([
          :address,
          :credit_amount,
          :san_amount,
          :san_price,
          :trx_datetime,
          :trx_hash,
          :user_id
        ])

      assert result == %{
               address: "0x1",
               credit_amount: 8000,
               san_amount: 1000,
               san_price: 4,
               trx_datetime: ~U[2022-05-23 05:43:40Z],
               trx_hash: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f",
               user_id: user.id
             }
    end)
  end
end
