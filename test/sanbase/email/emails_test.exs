defmodule Sanbase.EmailsTest do
  use SanbaseWeb.ConnCase
  use Oban.Testing, repo: Sanbase.Repo

  import Mock
  import Mox
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.Email.Template

  import Sanbase.DateTimeUtils, only: [days_after: 1]

  alias Sanbase.Billing.Subscription
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup_with_mocks([
    {StripeApi, [:passthrough],
     [
       create_customer_with_card: fn _, _ ->
         StripeApiTestResponse.create_or_update_customer_resp()
       end
     ]},
    {StripeApi, [:passthrough],
     [create_subscription: fn _ -> StripeApiTestResponse.create_subscription_resp() end]},
    {StripeApi, [:passthrough],
     [
       fetch_stripe_customer: fn _ ->
         {:ok, %{default_source: nil, invoice_settings: %{default_payment_method: "123"}}}
       end
     ]},
    {Sanbase.TemplateMailer, [], [send: fn _, _, _ -> {:ok, :email_sent} end]}
  ]) do
    not_registered_user = insert(:user_registration_not_finished, email: "example@santiment.net")

    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, not_registered_user: not_registered_user}
  end

  describe "schedule emails" do
    test "on Sanbase PRO trial started", context do
      expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)

      Subscription.create(%{
        stripe_id: "123",
        user_id: context.user.id,
        plan_id: 201,
        status: "trialing",
        trial_end: days_after(14)
      })

      args = %{user_id: context.user.id}

      vars1 = %{
        name: context.user.username,
        username: context.user.username,
        subscription_type: "Sanbase PRO"
      }

      args1 = Map.merge(args, %{template: trial_started_template(), vars: vars1})
      assert_enqueued([worker: Sanbase.Mailer, args: args1], 500)

      vars2 = %{
        name: context.user.username,
        username: context.user.username,
        subscription_type: "Sanbase PRO",
        subscription_duration: "monthly"
      }

      args2 = Map.merge(args, %{template: end_of_trial_template(), vars: vars2})

      assert_enqueued(
        [worker: Sanbase.Mailer, args: args2, scheduled_at: {days_after(11), delta: 10}],
        100
      )
    end

    test "on Sanbase PRO subscription started", context do
      expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)
      query = subscribe_mutation(context.plans.plan_pro_sanbase.id)

      execute_mutation(context.conn, query)

      args = %{
        user_id: context.user.id,
        template: pro_subscription_stared_template(),
        vars: %{
          name: context.user.username,
          username: context.user.username,
          subscription_type: "Sanbase PRO",
          subscription_duration: "month"
        }
      }

      assert_enqueued([worker: Sanbase.Mailer, args: args], 100)
    end

    test "on API PRO subscription started", context do
      expect(Sanbase.Email.MockMailjetApi, :subscribe, fn _, _ -> :ok end)
      query = subscribe_mutation(context.plans.plan_pro.id)

      execute_mutation(context.conn, query)

      assert [] = all_enqueued(worker: Sanbase.Mailer)
    end
  end

  describe "performing email jobs" do
    test "send trial started", context do
      insert(:subscription_pro_sanbase, user: context.user, status: "trialing")

      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => trial_started_template()
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "send trial end", context do
      insert(:subscription_pro_sanbase, user: context.user, status: "trialing")

      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => end_of_trial_template()
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send trial started", context do
      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => trial_started_template()
               })

      refute called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send trial end when scheduled for cancellation", context do
      insert(:subscription_pro_sanbase,
        user: context.user,
        status: "trialing",
        cancel_at_period_end: true
      )

      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => end_of_trial_template()
               })

      refute called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end
  end

  defp subscribe_mutation(plan_id) do
    """
    mutation {
      subscribe(card_token: "card_token", plan_id: #{plan_id}) {
        status
      }
    }
    """
  end
end
