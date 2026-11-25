defmodule Sanbase.Billing.SanBurnCreditTransactionTest do
  use Sanbase.DataCase, async: false
  import Sanbase.Factory

  alias Sanbase.Billing.Subscription.SanBurnCreditTransaction
  alias Sanbase.Accounts.EthAccount
  alias Sanbase.Repo

  @trx_hash "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
  @price_data %{price_usd: 4, price_btc: 0.03, marketcap: 100, volume: 100}

  setup do
    user =
      insert(:user,
        eth_accounts: [%EthAccount{address: "0x1"}],
        stripe_customer_id: "s1"
      )

    timestamp = ~U[2022-05-23 05:43:40Z] |> DateTime.to_unix()
    rows = [[timestamp, "0x1", 1000, @trx_hash]]

    %{user: user, rows: rows}
  end

  defp mocks(rows, add_credit_result, balance_history_result \\ {:ok, []}) do
    Sanbase.Mock.prepare_mock2(&Sanbase.Price.last_record_before/2, {:ok, @price_data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.StripeApi.add_credit/3, add_credit_result)
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.StripeApi.list_all_customer_balance_transactions/1,
      balance_history_result
    )
  end

  test "credits and records a burn", %{user: user, rows: rows} do
    mocks(rows, {:ok, %{id: "cbtxn_1"}})
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
          :status,
          :stripe_credit_id,
          :trx_datetime,
          :trx_hash,
          :user_id
        ])

      assert result == %{
               address: "0x1",
               credit_amount: 8000,
               san_amount: 1000,
               san_price: 4,
               status: "credited",
               stripe_credit_id: "cbtxn_1",
               trx_datetime: ~U[2022-05-23 05:43:40Z],
               trx_hash: @trx_hash,
               user_id: user.id
             }

      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, ["s1", -800_000, @trx_hash]) == 1
    end)
  end

  test "running the job twice credits the burn once", %{rows: rows} do
    mocks(rows, {:ok, %{id: "cbtxn_1"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()
      SanBurnCreditTransaction.run()

      assert [%{status: "credited"}] = SanBurnCreditTransaction.all()
      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 1
    end)
  end

  test "the same burn returned twice in one run is credited once", %{rows: rows} do
    mocks(rows ++ rows, {:ok, %{id: "cbtxn_1"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()

      assert [%{status: "credited"}] = SanBurnCreditTransaction.all()
      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 1
    end)
  end

  test "a failed Stripe balance history read marks the burn failed and credits nothing", %{
    rows: rows
  } do
    mocks(rows, {:ok, %{id: "cbtxn_1"}}, {:error, :timeout})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()

      assert [%{status: "failed", stripe_credit_id: nil}] = SanBurnCreditTransaction.all()
      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 0
    end)
  end

  # A concurrent run that passed `exist?/1` before the other run committed.
  test "saving an already recorded burn does not credit again", %{user: user, rows: rows} do
    {:ok, _} =
      SanBurnCreditTransaction.create(%{
        address: "0x1",
        trx_hash: @trx_hash,
        san_amount: 1000,
        san_price: 4,
        credit_amount: 8000,
        trx_datetime: ~U[2022-05-23 05:43:40Z],
        user_id: user.id
      })

    mocks(rows, {:ok, %{id: "cbtxn_1"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      {:ok, [burn_trx]} = SanBurnCreditTransaction.fetch_burn_trxs()

      assert {:error, :already_claimed} = SanBurnCreditTransaction.save(burn_trx)

      assert [%{status: "credited"}] = SanBurnCreditTransaction.all()
      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 0
    end)
  end

  test "a failed Stripe credit marks the burn failed and the next run retries", %{rows: rows} do
    mocks(rows, {:error, :timeout})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()

      assert [%{status: "failed", stripe_credit_id: nil}] = SanBurnCreditTransaction.all()
      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 1
    end)

    mocks(rows, {:ok, %{id: "cbtxn_2"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()

      assert [%{status: "credited", stripe_credit_id: "cbtxn_2"}] = SanBurnCreditTransaction.all()
      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 1
    end)
  end

  test "a stale pending burn from a crashed run is reclaimed and credited", %{
    user: user,
    rows: rows
  } do
    {:ok, record} =
      SanBurnCreditTransaction.create(%{
        address: "0x1",
        trx_hash: @trx_hash,
        san_amount: 1000,
        san_price: 4,
        credit_amount: 8000,
        trx_datetime: ~U[2022-05-23 05:43:40Z],
        status: "pending",
        user_id: user.id
      })

    stale_time =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-600, :second)
      |> NaiveDateTime.truncate(:second)

    Repo.update_all(SanBurnCreditTransaction, set: [updated_at: stale_time])
    assert record.status == "pending"

    mocks(rows, {:ok, %{id: "cbtxn_recovered"}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()

      assert [%{status: "credited", stripe_credit_id: "cbtxn_recovered"}] =
               SanBurnCreditTransaction.all()

      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 1
    end)
  end

  describe "double credit reproduction" do
    setup do
      ledger = start_supervised!({Agent, fn -> %{credits: [], calls: 0, keys: %{}} end})
      %{ledger: ledger}
    end

    test "a burn is claimed in the database before Stripe is called, blocking a concurrent run",
         %{rows: rows, ledger: ledger} do
      test_pid = self()

      create_fun = fn customer, params, opts ->
        assert [%{trx_hash: @trx_hash, status: "pending"}] = SanBurnCreditTransaction.all()
        send(test_pid, {:stripe_call, self()})

        receive do
          :continue -> fake_stripe_create(ledger, customer, params, opts)
        end
      end

      base_mocks(rows)
      |> stripe_mocks(ledger, create_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        first_task = Task.async(&SanBurnCreditTransaction.run/0)
        assert_receive {:stripe_call, first_pid}, 5_000

        # A second run arriving while the first is in-flight with Stripe must skip it.
        SanBurnCreditTransaction.run()
        refute_receive {:stripe_call, _}, 100

        send(first_pid, :continue)
        Task.await(first_task, 10_000)

        assert length(ledger_credits(ledger)) == 1

        assert [%{status: "credited", stripe_credit_id: "cbtxn_1"}] =
                 SanBurnCreditTransaction.all()
      end)
    end

    test "a credit that Stripe applied but reported as failed is not applied again",
         %{rows: rows, ledger: ledger} do
      create_fun = fn customer, params, opts ->
        result = fake_stripe_create(ledger, customer, params, opts)

        case Agent.get_and_update(ledger, &{&1.calls, %{&1 | calls: &1.calls + 1}}) do
          0 -> {:error, :timeout}
          _ -> result
        end
      end

      base_mocks(rows)
      |> stripe_mocks(ledger, create_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()
        assert [%{status: "failed"}] = SanBurnCreditTransaction.all()

        SanBurnCreditTransaction.run()

        assert length(ledger_credits(ledger)) == 1

        assert [%{status: "credited", stripe_credit_id: "cbtxn_1"}] =
                 SanBurnCreditTransaction.all()
      end)
    end

    test "a burn credited by hand in Stripe is recorded without a new credit",
         %{rows: rows, ledger: ledger} do
      manual_credit = %{
        id: "cbtxn_manual",
        customer: "s1",
        amount: -400_000,
        description: "Burned 1000 SAN https://etherscan.io/tx/#{@trx_hash}"
      }

      Agent.update(ledger, &%{&1 | credits: [manual_credit]})

      create_fun = fn customer, params, opts ->
        fake_stripe_create(ledger, customer, params, opts)
      end

      base_mocks(rows)
      |> stripe_mocks(ledger, create_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert ledger_credits(ledger) == [manual_credit]
        assert [burn_trx] = SanBurnCreditTransaction.all()
        assert burn_trx.trx_hash == @trx_hash
        assert burn_trx.credit_amount == 4000.0
        assert burn_trx.status == "credited"
        assert burn_trx.stripe_credit_id == "cbtxn_manual"
      end)
    end

    test "a stale takeover during a stalled Stripe call does not credit twice",
         %{rows: rows, ledger: ledger} do
      test_pid = self()

      create_fun = fn customer, params, opts ->
        call = Agent.get_and_update(ledger, &{&1.calls, %{&1 | calls: &1.calls + 1}})

        if call == 0 do
          send(test_pid, {:stripe_call, self()})

          receive do
            :continue -> :ok
          end
        end

        fake_stripe_create(ledger, customer, params, opts)
      end

      base_mocks(rows)
      |> stripe_mocks(ledger, create_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        first_task = Task.async(&SanBurnCreditTransaction.run/0)
        assert_receive {:stripe_call, first_pid}, 5_000

        # The first run stalls past the stale threshold, so a second run takes over.
        make_stale()
        SanBurnCreditTransaction.run()

        send(first_pid, :continue)
        Task.await(first_task, 10_000)

        assert [credit] = ledger_credits(ledger)
        assert Agent.get(ledger, & &1.calls) == 2

        assert [%{status: "credited", stripe_credit_id: stripe_credit_id}] =
                 SanBurnCreditTransaction.all()

        assert stripe_credit_id == credit.id
      end)
    end
  end

  test "the Stripe credit is sent with an idempotency key derived from the burn hash" do
    create_fun = fn "s1", _params, opts ->
      send(self(), {:idempotency_key, opts[:idempotency_key]})
      {:ok, %{id: "cbtxn_1"}}
    end

    Sanbase.Mock.prepare_mock(Stripe.CustomerBalanceTransaction, :create, create_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.StripeApi.add_credit("s1", -100, String.upcase(@trx_hash))
      expected = "san-burn-credit-#{@trx_hash}"
      assert_received {:idempotency_key, ^expected}
    end)
  end

  test "a retry credits the stored amount, not one from a changed price", %{
    user: user,
    rows: rows
  } do
    insert_claim(user, "failed")

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Price.last_record_before/2,
      {:ok, %{@price_data | price_usd: 10}}
    )
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.StripeApi.add_credit/3, {:ok, %{id: "cbtxn_1"}})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.StripeApi.list_all_customer_balance_transactions/1,
      {:ok, []}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      SanBurnCreditTransaction.run()

      assert [%{status: "credited", credit_amount: 8000.0, san_price: 4.0}] =
               SanBurnCreditTransaction.all()

      assert :meck.num_calls(Sanbase.StripeApi, :add_credit, ["s1", -800_000, @trx_hash]) == 1
    end)
  end

  describe "a claim whose address moved to another user" do
    setup %{user: user} do
      Repo.delete_all(EthAccount)

      other_user =
        insert(:user, eth_accounts: [%EthAccount{address: "0x1"}], stripe_customer_id: "s2")

      %{user: user, other_user: other_user}
    end

    test "a failed claim is left failed and nothing is credited", %{user: user, rows: rows} do
      insert_claim(user, "failed")

      mocks(rows, {:ok, %{id: "cbtxn_1"}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert [%{status: "failed", user_id: user_id, stripe_credit_id: nil}] =
                 SanBurnCreditTransaction.all()

        assert user_id == user.id
        assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 0
      end)
    end

    test "a stale pending claim is marked failed and nothing is credited", %{
      user: user,
      rows: rows
    } do
      insert_claim(user, "pending")
      make_stale()

      mocks(rows, {:ok, %{id: "cbtxn_1"}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert [%{status: "failed", user_id: user_id}] = SanBurnCreditTransaction.all()
        assert user_id == user.id
        assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 0
      end)
    end
  end

  describe "retrying claims outside the ClickHouse window" do
    test "a failed claim from the last 7 days is retried", %{user: user} do
      insert_claim(user, "failed", trx_datetime: days_ago(3))

      mocks([], {:ok, %{id: "cbtxn_1"}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert [%{status: "credited", stripe_credit_id: "cbtxn_1"}] =
                 SanBurnCreditTransaction.all()

        assert :meck.num_calls(Sanbase.StripeApi, :add_credit, ["s1", -800_000, @trx_hash]) == 1
      end)
    end

    test "a stale pending claim from the last 7 days is retried", %{user: user} do
      insert_claim(user, "pending", trx_datetime: days_ago(3))
      make_stale()

      mocks([], {:ok, %{id: "cbtxn_1"}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert [%{status: "credited"}] = SanBurnCreditTransaction.all()
        assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 1
      end)
    end

    test "a fresh pending claim is not retried", %{user: user} do
      insert_claim(user, "pending", trx_datetime: days_ago(3))

      mocks([], {:ok, %{id: "cbtxn_1"}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert [%{status: "pending"}] = SanBurnCreditTransaction.all()
        assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 0
      end)
    end

    test "a failed claim older than 7 days is not retried", %{user: user} do
      insert_claim(user, "failed", trx_datetime: days_ago(8))

      mocks([], {:ok, %{id: "cbtxn_1"}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        SanBurnCreditTransaction.run()

        assert [%{status: "failed"}] = SanBurnCreditTransaction.all()
        assert :meck.num_calls(Sanbase.StripeApi, :add_credit, :_) == 0
      end)
    end
  end

  test "list_all_customer_balance_transactions paginates across multiple pages" do
    list_fun = fn
      "s1", %{limit: 100, starting_after: "cbtxn_2"} ->
        {:ok, %{data: [%{id: "cbtxn_3"}], has_more: false}}

      "s1", %{limit: 100} ->
        {:ok, %{data: [%{id: "cbtxn_1"}, %{id: "cbtxn_2"}], has_more: true}}
    end

    Sanbase.Mock.prepare_mock(Stripe.CustomerBalanceTransaction, :list, list_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      assert {:ok, [%{id: "cbtxn_1"}, %{id: "cbtxn_2"}, %{id: "cbtxn_3"}]} =
               Sanbase.StripeApi.list_all_customer_balance_transactions("s1")
    end)
  end

  defp base_mocks(rows) do
    Sanbase.Mock.prepare_mock2(&Sanbase.Price.last_record_before/2, {:ok, @price_data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/3, {:ok, %{rows: rows}})
  end

  defp stripe_mocks(state, ledger, create_fun) do
    list_fun = fn customer ->
      {:ok, Enum.filter(ledger_credits(ledger), &(&1.customer == customer))}
    end

    state
    |> Sanbase.Mock.prepare_mock(
      Sanbase.StripeApi,
      :list_all_customer_balance_transactions,
      list_fun
    )
    |> Sanbase.Mock.prepare_mock(Stripe.CustomerBalanceTransaction, :create, create_fun)
  end

  # Mirrors Stripe idempotency: a request with a key seen before returns the
  # credit of the first request instead of creating a new one.
  defp fake_stripe_create(ledger, customer, params, opts) do
    key = Keyword.fetch!(opts, :idempotency_key)

    Agent.get_and_update(ledger, fn state ->
      case Map.fetch(state.keys, key) do
        {:ok, credit} ->
          {{:ok, credit}, state}

        :error ->
          credit = %{
            id: "cbtxn_#{length(state.credits) + 1}",
            customer: customer,
            amount: params.amount,
            description: params.description
          }

          {{:ok, credit},
           %{state | credits: [credit | state.credits], keys: Map.put(state.keys, key, credit)}}
      end
    end)
  end

  defp insert_claim(user, status, opts \\ []) do
    {:ok, record} =
      SanBurnCreditTransaction.create(%{
        address: "0x1",
        trx_hash: @trx_hash,
        san_amount: 1000,
        san_price: 4,
        credit_amount: 8000,
        trx_datetime: Keyword.get(opts, :trx_datetime, ~U[2022-05-23 05:43:40Z]),
        status: status,
        user_id: user.id
      })

    record
  end

  defp make_stale() do
    stale_time =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-600, :second)
      |> NaiveDateTime.truncate(:second)

    Repo.update_all(SanBurnCreditTransaction, set: [updated_at: stale_time])
  end

  defp days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 86_400, :second)
    |> DateTime.truncate(:second)
  end

  defp ledger_credits(ledger), do: Agent.get(ledger, & &1.credits)
end
