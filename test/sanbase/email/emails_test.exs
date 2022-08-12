defmodule Sanbase.EmailsTest do
  use SanbaseWeb.ConnCase
  use Oban.Testing, repo: Sanbase.Repo

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.Email.Template

  import Sanbase.DateTimeUtils, only: [days_after: 1]

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Subscription
  alias Sanbase.Accounts.EmailJobs
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  setup_with_mocks([
    {StripeApi, [:passthrough],
     [create_customer: fn _, _ -> StripeApiTestResponse.create_or_update_customer_resp() end]},
    {StripeApi, [:passthrough],
     [create_subscription: fn _ -> StripeApiTestResponse.create_subscription_resp() end]},
    {StripeApi, [:passthrough],
     [fetch_default_card: fn _ -> {:ok, %{default_source: "123"}} end]},
    {Sanbase.TemplateMailer, [], [send: fn _, _, _ -> {:ok, :email_sent} end]}
  ]) do
    not_registered_user = insert(:user, email: "example@santiment.net", is_registered: false)
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, not_registered_user: not_registered_user}
  end

  describe "schedule emails" do
    test "on user registration", context do
      {:ok, user} = context.not_registered_user |> User.update_email_token()

      execute_mutation(build_conn(), email_login_verify_mutation(user))

      args = %{
        user_id: context.not_registered_user.id,
        vars: %{
          name: context.not_registered_user.username,
          username: context.not_registered_user.username
        }
      }

      assert_enqueued(
        [
          worker: Sanbase.Mailer,
          args: Map.put(args, :template, sign_up_templates()[:welcome_email])
        ],
        500
      )

      assert_enqueued(
        [
          worker: Sanbase.Mailer,
          args: Map.put(args, :template, sign_up_templates()[:first_education_email]),
          scheduled_at: {days_after(4), delta: 10}
        ],
        500
      )

      assert_enqueued(
        [
          worker: Sanbase.Mailer,
          args: Map.put(args, :template, sign_up_templates()[:trial_suggestion]),
          scheduled_at: {days_after(6), delta: 10}
        ],
        500
      )

      assert_enqueued(
        [
          worker: Sanbase.Mailer,
          args: Map.put(args, :template, sign_up_templates()[:second_education_email]),
          scheduled_at: {days_after(7), delta: 10}
        ],
        500
      )
    end

    test "on Sanbase PRO trial started", context do
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

      vars3 = %{
        name: context.user.username,
        username: context.user.username,
        end_subscription_date: days_after(14) |> EmailJobs.format_date()
      }

      args3 = Map.merge(args, %{template: during_trial_annual_discount_template(), vars: vars3})

      assert_enqueued(
        [worker: Sanbase.Mailer, args: args3, scheduled_at: {days_after(12), delta: 10}],
        100
      )

      vars4 = %{
        name: context.user.username,
        username: context.user.username,
        date: days_after(30) |> EmailJobs.format_date()
      }

      args4 = Map.merge(args, %{template: after_trial_annual_discount_template(), vars: vars4})

      assert_enqueued(
        [worker: Sanbase.Mailer, args: args4, scheduled_at: {days_after(24), delta: 10}],
        100
      )
    end

    test "on Sanbase PRO subscription started", context do
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
  end

  describe "performing email jobs" do
    test "send welcome email", context do
      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => sign_up_templates()[:welcome_email]
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send welcome email when user has no email" do
      user_no_email = insert(:user, email: nil)

      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => user_no_email.id,
                 "template" => sign_up_templates()[:welcome_email]
               })
    end

    test "send 1st edu email", context do
      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => sign_up_templates()[:first_education_email]
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "send 2nd edu email", context do
      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => sign_up_templates()[:second_education_email]
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send edu emails if user opted out", context do
      insert(:user_settings, user: context.user, settings: %{is_subscribed_edu_emails: false})

      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => sign_up_templates()[:first_education_email]
               })

      refute called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

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

    test "send discount 50% email", context do
      insert(:subscription_pro_sanbase,
        user: context.user,
        status: "trialing",
        trial_end: days_after(10)
      )

      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => during_trial_annual_discount_template()
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "send discount 35% email", context do
      insert(:subscription_pro_sanbase,
        user: context.user,
        status: "trialing",
        trial_end: days_after(-10)
      )

      assert {:ok, :email_sent} =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => after_trial_annual_discount_template()
               })

      assert_called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send discount 50% email", context do
      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => during_trial_annual_discount_template()
               })

      refute called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send discount 35% email", context do
      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => after_trial_annual_discount_template()
               })

      refute called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end

    test "do not send discount 35% email if more than 30 days passed", context do
      insert(:subscription_pro_sanbase,
        user: context.user,
        status: "trialing",
        trial_end: days_after(-20)
      )

      assert :ok =
               perform_job(Sanbase.Mailer, %{
                 "user_id" => context.user.id,
                 "template" => after_trial_annual_discount_template()
               })

      refute called(Sanbase.TemplateMailer.send(context.user.email, :_, :_))
    end
  end

  defp email_login_verify_mutation(user) do
    """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        token
      }
    }
    """
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
