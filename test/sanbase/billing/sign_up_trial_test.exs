defmodule Sanbase.Billing.SignUpTrialTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.Subscription.SignUpTrial
  alias Sanbase.Repo

  setup_with_mocks([
    {Sanbase.MandrillApi, [:passthrough], send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
  ]) do
    user = insert(:user)

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

      assert_called(Sanbase.MandrillApi.send("first-edu-email", :_, :_, :_))
      assert sign_up_trial.sent_first_education_email
    end

    test "email marked as sent is not sent twice", context do
      sign_up_trial(context, trial_day: 4, marked_as_sent: :sent_first_education_email)

      SignUpTrial.send_email_on_trial_day()

      refute called(Sanbase.MandrillApi.send("first-edu-email", :_, :_, :_))
    end

    test "day 7 email is sent successfully and marked as sent", context do
      sign_up_trial(context, trial_day: 7)
      SignUpTrial.send_email_on_trial_day()

      sign_up_trial = SignUpTrial |> Repo.all() |> hd()

      assert_called(Sanbase.MandrillApi.send("second-edu-email", :_, :_, :_))
      assert sign_up_trial.sent_second_education_email
    end

    test "card will be charged email is sent successfully if user has a card", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: "alabala"}} end}
      ]) do
        sign_up_trial(context, trial_day: 13)
        SignUpTrial.send_email_on_trial_day()

        sign_up_trial = SignUpTrial |> Repo.all() |> hd()

        assert_called(Sanbase.MandrillApi.send("trial-finished", :_, :_, :_))
        assert sign_up_trial.sent_cc_will_be_charged
      end
    end

    test "card will be charged is not sent to users without card", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: nil}} end}
      ]) do
        sign_up_trial(context, trial_day: 13)
        SignUpTrial.send_email_on_trial_day()

        sign_up_trial = SignUpTrial |> Repo.all() |> hd()

        refute called(Sanbase.MandrillApi.send("trial-finished", :_, :_, :_))
        refute sign_up_trial.sent_cc_will_be_charged
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
