defmodule Sanbase.Billing.PromoTrialTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  setup context do
    user = insert(:user, stripe_customer_id: "cus_test_promo")
    Map.put(context, :user, user)
  end

  describe "create_promo_trial/1 cancels at trial end" do
    setup_with_mocks(
      [
        {StripeApi, [:passthrough],
         [
           create_subscription: fn args ->
             send(self(), {:stripe_create_subscription, args})
             StripeApiTestResponse.create_subscription_resp(status: "trialing")
           end
         ]}
      ],
      context
    ) do
      {:ok, context}
    end

    test "passes cancel_at 60s before trial_end for list-of-plans variant", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [_subscription]} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plans: [plan.id],
                 trial_days: 14
               })

      assert_receive {:stripe_create_subscription, args}
      assert is_integer(args.trial_end)
      assert args.cancel_at == args.trial_end - 60
      assert args.customer == "cus_test_promo"

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 14
      assert promo_trial.plans == ["Sanbase by Santiment / PRO (month)"]
    end

    test "passes cancel_at 60s before trial_end for single plan_id variant", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, _subscription} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plan_id: plan.id,
                 trial_days: 7
               })

      assert_receive {:stripe_create_subscription, args}
      assert args.cancel_at == args.trial_end - 60

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 7
      assert promo_trial.plans == ["Sanbase by Santiment / PRO (month)"]
    end

    test "string-keyed params variant also sets cancel_at 60s before trial_end", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [_subscription]} =
               PromoTrial.create_promo_trial(%{
                 "user_id" => context.user.id,
                 "plans" => [plan.id],
                 "trial_days" => 30
               })

      assert_receive {:stripe_create_subscription, args}
      assert args.cancel_at == args.trial_end - 60

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 30
      assert promo_trial.plans == ["Sanbase by Santiment / PRO (month)"]
    end

    test "persists one promo_trials row for multiple plans", context do
      sanbase_plan = context.plans.plan_pro_sanbase
      api_plan = context.plans.plan_pro

      assert {:ok, subscriptions} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plans: [sanbase_plan.id, api_plan.id],
                 trial_days: 14
               })

      assert length(subscriptions) == 2
      assert Repo.aggregate(PromoTrial, :count, :id) == 1

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 14
      assert length(promo_trial.plans) == 2
      assert "Sanbase by Santiment / PRO (month)" in promo_trial.plans
      assert "Sanapi by Santiment / PRO (month)" in promo_trial.plans
    end

    test "links the created subscriptions to the promo trial record", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [subscription]} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plans: [plan.id],
                 trial_days: 14
               })

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.subscription_ids == [subscription.id]
      assert [%{id: id}] = PromoTrial.subscriptions(promo_trial)
      assert id == subscription.id
    end

    test "trial_end timestamp roughly matches requested trial_days", context do
      plan = context.plans.plan_pro_sanbase
      trial_days = 14

      {:ok, [_subscription]} =
        PromoTrial.create_promo_trial(%{
          user_id: context.user.id,
          plans: [plan.id],
          trial_days: trial_days
        })

      assert_receive {:stripe_create_subscription, args}
      expected = DateTime.utc_now() |> DateTime.add(trial_days * 24 * 3600, :second)
      delta = abs(args.trial_end - DateTime.to_unix(expected))
      assert delta < 60
    end
  end

  describe "managing granted promo trials" do
    setup context do
      subscription = insert_promo_subscription(context, "sub_promo_test")
      promo_trial = insert_promo_trial(context, 14, [subscription.id], 0)

      context
      |> Map.put(:subscription, subscription)
      |> Map.put(:promo_trial, promo_trial)
    end

    test "extending the trial moves trial_end and cancel_at in Stripe", context do
      with_mock StripeApi, [:passthrough],
        update_subscription: fn stripe_id, params ->
          send(self(), {:stripe_update_subscription, stripe_id, params})
          StripeApiTestResponse.update_subscription_resp(status: "trialing")
        end do
        assert {:ok, promo_trial} = PromoTrial.update_trial_days(context.promo_trial, 30)
        assert promo_trial.trial_days == 30

        assert_receive {:stripe_update_subscription, "sub_promo_test", params}
        expected_trial_end = PromoTrial.trial_end_for(promo_trial, 30) |> DateTime.to_unix()
        assert params.trial_end == expected_trial_end
        assert params.cancel_at == expected_trial_end - 60
      end
    end

    test "shortening the trial is applied to Stripe as well", context do
      with_mock StripeApi, [:passthrough],
        update_subscription: fn _stripe_id, params ->
          send(self(), {:stripe_update_subscription, params})
          StripeApiTestResponse.update_subscription_resp(status: "trialing")
        end do
        assert {:ok, promo_trial} = PromoTrial.update_trial_days(context.promo_trial, 3)
        assert promo_trial.trial_days == 3

        assert_receive {:stripe_update_subscription, params}
        assert params.trial_end == PromoTrial.trial_end_for(promo_trial, 3) |> DateTime.to_unix()
      end
    end

    test "a new trial length that already lies in the past is refused", context do
      # Granted 40 days ago - a 10 day trial would have ended 30 days ago.
      promo_trial = insert_promo_trial(context, 60, [context.subscription.id], -40)

      with_mock StripeApi, [:passthrough],
        update_subscription: fn _stripe_id, _params ->
          send(self(), :stripe_called)
          StripeApiTestResponse.update_subscription_resp(status: "trialing")
        end do
        assert {:error, error} = PromoTrial.update_trial_days(promo_trial, 10)
        assert error =~ "Cancel the subscriptions instead"
        refute_receive :stripe_called

        assert Repo.get(PromoTrial, promo_trial.id).trial_days == 60
      end
    end

    test "trials that are no longer trialing cannot be changed", context do
      context.subscription
      |> Ecto.Changeset.change(status: :canceled)
      |> Repo.update!()

      assert {:error, error} = PromoTrial.update_trial_days(context.promo_trial, 30)
      assert error =~ "No trialing subscriptions left"
    end

    test "cancelling cancels every subscription in Stripe and syncs them", context do
      with_mock StripeApi, [:passthrough],
        cancel_subscription_immediately: fn stripe_id, _params ->
          send(self(), {:stripe_cancel, stripe_id})
          StripeApiTestResponse.cancel_subscription_immediately_resp(stripe_id: stripe_id)
        end do
        assert {:ok, 1} = PromoTrial.cancel_subscriptions(context.promo_trial)

        assert_receive {:stripe_cancel, "sub_promo_test"}
        assert Repo.get(Sanbase.Billing.Subscription, context.subscription.id).status == :canceled
      end
    end

    test "cancelling an already cancelled promo trial is a no-op error", context do
      context.subscription
      |> Ecto.Changeset.change(status: :canceled)
      |> Repo.update!()

      assert {:error, error} = PromoTrial.cancel_subscriptions(context.promo_trial)
      assert error =~ "already cancelled"
    end

    test "records without stored subscription ids match by creation time", context do
      promo_trial = insert_promo_trial(context, 14, [], 0)

      assert [%{id: id}] = PromoTrial.subscriptions(promo_trial)
      assert id == context.subscription.id

      # A subscription created long before the promo trial is not a match.
      old_promo_trial = insert_promo_trial(context, 14, [], -40)
      assert PromoTrial.subscriptions(old_promo_trial) == []
    end

    test "a paid subscription bought at the same time is not taken for a promo trial", context do
      insert(:subscription,
        user: context.user,
        plan: context.plans.plan_pro_sanbase,
        stripe_id: "sub_paid",
        status: "active",
        trial_end: nil
      )

      promo_trial = insert_promo_trial(context, 14, [], 0)

      assert [%{stripe_id: "sub_promo_test"}] = PromoTrial.subscriptions(promo_trial)
    end

    test "list_with_subscriptions paginates and filters by user", context do
      {rows, total} = PromoTrial.list_with_subscriptions(search: context.user.email)

      assert total == 1
      assert [%{promo_trial: promo_trial, subscriptions: [subscription]}] = rows
      assert promo_trial.id == context.promo_trial.id
      assert subscription.id == context.subscription.id
      assert subscription.plan.product.name

      assert {[], 0} = PromoTrial.list_with_subscriptions(search: "no-such-user@example.com")
    end
  end

  defp insert_promo_subscription(context, stripe_id) do
    insert(:subscription,
      user: context.user,
      plan: context.plans.plan_pro_sanbase,
      stripe_id: stripe_id,
      status: "trialing",
      trial_end: Timex.shift(Timex.now(), days: 14) |> DateTime.truncate(:second)
    )
  end

  defp insert_promo_trial(context, trial_days, subscription_ids, days_ago) do
    granted_at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(days_ago * 24 * 3600, :second)
      |> NaiveDateTime.truncate(:second)

    Repo.insert!(%PromoTrial{
      user_id: context.user.id,
      trial_days: trial_days,
      plans: ["Sanbase by Santiment / PRO (month)"],
      subscription_ids: subscription_ids,
      inserted_at: granted_at,
      updated_at: granted_at
    })
  end
end
