defmodule Sanbase.Billing.Subscription.PurchaseLockTest do
  @moduledoc ~s"""
  Proves that two concurrent SanAPI new-offering purchases cannot both charge.

  ## Why the competing holder is a raw Postgrex connection

  A session-level advisory lock belongs to a *connection*, and it is re-entrant
  within one: the same session can take the same lock twice and succeed both times.
  Ecto's SQL sandbox hands every process in a test the same connection, so two
  `Task`s racing here would share one session, both acquire, and the test would
  pass whether or not the lock worked at all.

  So the second party is a real connection of its own, opened directly with
  Postgrex against the same database. That is the only arrangement in which
  `pg_try_advisory_lock` can actually answer `false`, and therefore the only one in
  which this test means anything.
  """

  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.PurchaseLock
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  # Mirrors PurchaseLock's own namespace. Duplicated rather than exposed: the
  # constant is an implementation detail, and a test that had to be handed it could
  # not notice it changing.
  @namespace 8412

  setup context do
    insert(:role_san_team)

    plan =
      insert(:plan_pro,
        id: 9901,
        name: "INSTITUTIONAL",
        product_id: context.product_api.id,
        interval: "month",
        amount: 79_900,
        is_private: false,
        is_deprecated: false,
        stripe_id: "plan_institutional_month_" <> Ecto.UUID.generate()
      )

    user = insert(:user, stripe_customer_id: "cus_lock_" <> Ecto.UUID.generate())

    %{plan: plan, user: user}
  end

  describe "with_lock/2" do
    test "runs the function and returns its value", %{user: user} do
      assert {:ok, :ran} = PurchaseLock.with_lock(user.id, fn -> {:ok, :ran} end)
    end

    test "refuses while another connection holds the same user's lock", %{user: user} do
      with_foreign_lock(user.id, fn ->
        assert {:error, message} = PurchaseLock.with_lock(user.id, fn -> flunk("ran anyway") end)
        assert message == PurchaseLock.busy_message()
      end)
    end

    test "a lock on one user does not block another", %{user: user} do
      other = insert(:user)

      with_foreign_lock(other.id, fn ->
        assert {:ok, :ran} = PurchaseLock.with_lock(user.id, fn -> {:ok, :ran} end)
      end)
    end

    test "releases the lock when the function returns", %{user: user} do
      # Asserted from another connection on purpose. A second `with_lock/2` in this
      # process would succeed even if nothing were released, because an advisory
      # lock is re-entrant within the session that holds it - so that assertion
      # would prove nothing at all.
      assert {:ok, :done} = PurchaseLock.with_lock(user.id, fn -> {:ok, :done} end)

      assert foreign_can_lock?(user.id)
    end

    test "releases the lock when the function raises", %{user: user} do
      # A crash mid-purchase must not leave the customer permanently unable to buy.
      assert_raise RuntimeError, fn ->
        PurchaseLock.with_lock(user.id, fn -> raise "boom" end)
      end

      assert foreign_can_lock?(user.id)
    end

    test "holds the lock while the function runs", %{user: user} do
      # The other half of the above: proves the lock is genuinely taken, not that
      # `with_lock/2` merely runs things and returns true from a stub.
      PurchaseLock.with_lock(user.id, fn ->
        refute foreign_can_lock?(user.id)
      end)
    end
  end

  describe "the Institutional purchase flow" do
    test "a second concurrent purchase creates no Stripe subscription at all", context do
      %{user: user, plan: plan} = context

      with_mocks([
        {StripeApi, [:passthrough],
         [
           update_customer_card: fn _, _ ->
             {:ok, %Stripe.Customer{id: "cus_should_not_happen"}}
           end,
           create_subscription: fn _ ->
             {:ok, %Stripe.Subscription{id: "sub_should_not_happen"}}
           end
         ]}
      ]) do
        with_foreign_lock(user.id, fn ->
          assert {:error, message} = Subscription.subscribe(user, plan, "card_token")
          assert message == PurchaseLock.busy_message()

          # The whole point: the loser never reaches Stripe, so there is no second
          # subscription to cancel and nothing to refund. `update_customer_card/2`
          # is the first Stripe call the flow would make - asserting on it proves
          # the refusal happens before *any* of them, not just before the charge.
          assert_not_called(StripeApi.create_subscription(:_))
          assert_not_called(StripeApi.update_customer_card(:_, :_))
        end)
      end

      assert institutional_subscriptions(user) == []
    end

    test "only one Institutional subscription remains billable after a serialized pair",
         context do
      %{user: user, plan: plan} = context

      # The winner and the loser, run in the order the lock imposes on them. The
      # second call is the one that matters: by the time it runs the first has
      # committed, so `ensure_plan_is_for_sale/2` can finally see it and refuses -
      # which is exactly what the lock exists to guarantee it can do.
      winner_id =
        with_mocks(stripe_mocks()) do
          assert {:ok, first} = Subscription.subscribe(user, plan, "card_token")
          assert first.status == :active

          assert {:error, %Subscription.Error{message: message}} =
                   Subscription.subscribe(user, plan, "card_token")

          # `has_active_subscriptions/2` catches this one, because both calls name
          # the same plan id and it runs first. The offering check is what catches a
          # *different* new-offering plan id - the yearly row, or a bundle - and that
          # case is covered in Sanbase.Billing.Plan.InstitutionalTest.
          assert message == "You are already subscribed to Sanapi by Santiment / INSTITUTIONAL"

          first.id
        end

      assert [%Subscription{id: ^winner_id}] = institutional_subscriptions(user)
    end

    test "the lock does not stand in the way of a legitimate purchase", context do
      %{user: user, plan: plan} = context

      with_mocks(stripe_mocks()) do
        assert {:ok, subscription} = Subscription.subscribe(user, plan, "card_token")
        assert subscription.plan.name == "INSTITUTIONAL"
      end

      assert length(institutional_subscriptions(user)) == 1
    end
  end

  # --- helpers ---

  defp stripe_mocks do
    [
      {StripeApi, [:passthrough],
       [
         create_product: fn _ -> Sanbase.StripeApiTestResponse.create_product_resp() end,
         create_plan: fn _ -> Sanbase.StripeApiTestResponse.create_plan_resp() end,
         create_customer_with_card: fn _, _ ->
           Sanbase.StripeApiTestResponse.create_or_update_customer_resp()
         end,
         # The one that actually fires here: the user already has a
         # stripe_customer_id, so the card token updates the customer rather than
         # creating one.
         update_customer_card: fn _, _ ->
           Sanbase.StripeApiTestResponse.create_or_update_customer_resp()
         end,
         create_coupon: fn _ -> Sanbase.StripeApiTestResponse.create_coupon_resp() end,
         retrieve_coupon: fn coupon -> {:ok, %Stripe.Coupon{id: coupon, percent_off: 20}} end,
         create_subscription: fn _ ->
           Sanbase.StripeApiTestResponse.create_subscription_resp()
         end
       ]},
      {Sanbase.Messaging.Discord, [:passthrough], [send_notification: fn _, _, _ -> :ok end]},
      {Sanbase.TemplateMailer, [:passthrough],
       send: fn _, _, _ -> {:ok, %{"status" => "sent"}} end}
    ]
  end

  defp institutional_subscriptions(user) do
    import Ecto.Query

    from(s in Subscription,
      join: p in Plan,
      on: p.id == s.plan_id,
      where: s.user_id == ^user.id and p.name == "INSTITUTIONAL",
      where: s.status in [:active, :past_due, :trialing],
      order_by: [asc: s.id]
    )
    |> Repo.all()
  end

  # Holds the user's advisory lock on a connection of its own for the duration of
  # `fun`, then releases it and disconnects.
  defp with_foreign_lock(user_id, fun) do
    {:ok, conn} = start_foreign_connection()

    %Postgrex.Result{rows: [[true]]} =
      Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1, $2)", [@namespace, user_id])

    try do
      fun.()
    after
      Postgrex.query!(conn, "SELECT pg_advisory_unlock($1, $2)", [@namespace, user_id])
      GenServer.stop(conn)
    end
  end

  defp foreign_can_lock?(user_id) do
    {:ok, conn} = start_foreign_connection()

    try do
      %Postgrex.Result{rows: [[acquired?]]} =
        Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1, $2)", [@namespace, user_id])

      if acquired? do
        Postgrex.query!(conn, "SELECT pg_advisory_unlock($1, $2)", [@namespace, user_id])
      end

      acquired?
    after
      GenServer.stop(conn)
    end
  end

  # `Repo.config/0` rather than `Application.get_env/2`: the connection details come
  # from DATABASE_URL at runtime, so the compile-time config names a role that does
  # not exist on a developer machine. Only the resolved config is usable.
  defp start_foreign_connection do
    Repo.config()
    |> Keyword.take([:username, :password, :hostname, :port, :database])
    |> Postgrex.start_link()
  end
end
