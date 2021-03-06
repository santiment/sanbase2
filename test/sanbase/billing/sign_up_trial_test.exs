defmodule Sanbase.Billing.SignUpTrialTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.Subscription.SignUpTrial
  alias Sanbase.Repo

  @moduletag capture_log: true

  setup_with_mocks([
    {Sanbase.MandrillApi, [:passthrough], send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
  ]) do
    user = insert(:user, stripe_customer_id: "test stripe id")

    %{
      user: user,
      subscription: insert(:subscription_pro_sanbase, user: user, status: "trialing")
    }
  end

  describe "#send_email_on_trial_day" do
    test "day 4 email is sent successfully and marked as sent", context do
      sign_up_trial(context, trial_day: 4)
      SignUpTrial.send_email_on_trial_day()

      sign_up_trial = SignUpTrial |> Repo.all() |> hd()

      assert_called(Sanbase.MandrillApi.send("first_edu_email", :_, :_))
      assert sign_up_trial.sent_first_education_email
    end

    test "email marked as sent is not sent twice", context do
      sign_up_trial(context, trial_day: 4, marked_as_sent: :sent_first_education_email)

      SignUpTrial.send_email_on_trial_day()

      refute called(Sanbase.MandrillApi.send("first_edu_email", :_, :_))
    end

    test "day 7 email is sent successfully and marked as sent", context do
      sign_up_trial(context, trial_day: 7)
      SignUpTrial.send_email_on_trial_day()

      sign_up_trial = SignUpTrial |> Repo.all() |> hd()

      assert_called(Sanbase.MandrillApi.send("second_edu_email", :_, :_))
      assert sign_up_trial.sent_second_education_email
    end
  end

  describe "#cancel_about_to_expire_trials" do
    test "cancel ~2 hours before trial expires and user has no CC", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: nil}} end},
        {Sanbase.StripeApi, [],
         delete_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "123"}} end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        subscription =
          insert(:subscription_pro_sanbase,
            user: context.user,
            status: "trialing",
            trial_end: Timex.shift(Timex.now(), hours: 1)
          )

        insert(:sign_up_trial,
          user_id: context.user.id,
          subscription: subscription
        )

        SignUpTrial.cancel_about_to_expire_trials()

        assert_called(Sanbase.StripeApi.delete_subscription(subscription.stripe_id))
        assert_called(Sanbase.MandrillApi.send("trial_finished_without_card", :_, :_))
      end
    end

    test "cancel even when user has CC", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: "card"}} end},
        {Sanbase.StripeApi, [],
         delete_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "123"}} end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        subscription =
          insert(:subscription_pro_sanbase,
            user: context.user,
            status: "trialing",
            trial_end: Timex.shift(Timex.now(), hours: 1)
          )

        insert(:sign_up_trial,
          user_id: context.user.id,
          subscription: subscription
        )

        SignUpTrial.cancel_about_to_expire_trials()

        assert_called(Sanbase.StripeApi.delete_subscription(subscription.stripe_id))
        assert_called(Sanbase.MandrillApi.send("trial_finished_without_card", :_, :_))
      end
    end

    test "cancel ~2 hours before trial expires when user has API plan", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: nil}} end},
        {Sanbase.StripeApi, [],
         delete_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "123"}} end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        subscription =
          insert(:subscription_pro,
            user: context.user,
            status: "trialing",
            trial_end: Timex.shift(Timex.now(), hours: 1)
          )

        SignUpTrial.cancel_about_to_expire_trials()

        assert_called(Sanbase.StripeApi.delete_subscription(subscription.stripe_id))
        refute called(Sanbase.MandrillApi.send("trial_finished_without_card", :_, :_))
      end
    end

    test "don't cancel trial for Sanbase PRO that does not have record in sign_up_trials",
         context do
      with_mocks([
        {Sanbase.StripeApi, [],
         delete_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "123"}} end}
      ]) do
        subscription =
          insert(:subscription_pro_sanbase,
            user: context.user,
            status: "trialing",
            trial_end: Timex.shift(Timex.now(), hours: 1)
          )

        SignUpTrial.cancel_about_to_expire_trials()

        refute called(Sanbase.StripeApi.delete_subscription(subscription.stripe_id))
        refute called(Sanbase.MandrillApi.send("trial_finished_without_card", :_, :_))
      end
    end
  end

  describe "#create_trial_subscription" do
    test "when everything is ok", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         create_subscription: fn _ ->
           Sanbase.StripeApiTestResponse.create_subscription_resp(stripe_id: "test id")
         end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        sut =
          SignUpTrial.create_trial_subscription(context.user.id)
          |> elem(1)
          |> Sanbase.Repo.preload(:subscription)

        assert sut.subscription.stripe_id == "test id"
      end
    end

    test "when user is already registered, no trial" do
      with_mocks([
        {Sanbase.StripeApi, [],
         create_subscription: fn _ ->
           Sanbase.StripeApiTestResponse.create_subscription_resp(stripe_id: "test id")
         end}
      ]) do
        user = insert(:user, is_registered: true)
        SignUpTrial.create_trial_subscription(user.id)
        refute called(Sanbase.StripeApi.create_subscription(:_))
      end
    end

    test "when there is a Stripe error", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         create_subscription: fn _ ->
           {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
         end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        {:error, error_msg} = SignUpTrial.create_trial_subscription(context.user.id)

        assert error_msg =~ "test error"
      end
    end
  end

  defp sign_up_trial(context, opts) do
    trial_day = Keyword.get(opts, :trial_day, 0)
    marked_as_sent = Keyword.get(opts, :marked_as_sent)

    inserted_at = Timex.shift(Timex.now(), days: -trial_day)

    params = %{
      user_id: context.user.id,
      subscription: context.subscription,
      inserted_at: inserted_at
    }

    params =
      if marked_as_sent do
        Map.merge(params, %{marked_as_sent => true})
      else
        params
      end

    insert(:sign_up_trial, params)
  end
end
