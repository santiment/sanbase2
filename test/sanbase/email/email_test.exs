defmodule Sanbase.EmailTest do
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
     [create_subscription: fn _ -> StripeApiTestResponse.create_subscription_resp() end]}
  ]) do
    not_registered_user = insert(:user, email: "example@santiment.net", is_registered: false)
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, not_registered_user: not_registered_user}
  end

  test "schedule emails on user registration", context do
    {:ok, user} = context.not_registered_user |> User.update_email_token()

    execute_mutation(build_conn(), email_login_verify_mutation(user))

    args = %{
      user_id: context.not_registered_user.id,
      vars: %{name: context.not_registered_user.username}
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

  test "schedule emails on Sanbase PRO trial started", context do
    Subscription.create(%{
      stripe_id: "123",
      user_id: context.user.id,
      plan_id: 201,
      status: "trialing",
      trial_end: days_after(14)
    })

    args = %{user_id: context.user.id}

    vars1 = %{name: context.user.username, subscription_type: "Sanbase PRO"}
    args1 = Map.merge(args, %{template: trial_started_template(), vars: vars1})
    assert_enqueued([worker: Sanbase.Mailer, args: args1], 500)

    vars2 = %{
      name: context.user.username,
      subscription_type: "Sanbase PRO",
      subscription_duration: "monthly"
    }

    args2 = Map.merge(args, %{template: end_of_trial_template(), vars: vars2})

    assert_enqueued(
      [worker: Sanbase.Mailer, args: args2, scheduled_at: {days_after(11), delta: 10}],
      100
    )

    vars3 = %{name: context.user.username, expire_at: days_after(14) |> EmailJobs.format_date()}
    args3 = Map.merge(args, %{template: during_trial_annual_discount_template(), vars: vars3})

    assert_enqueued(
      [worker: Sanbase.Mailer, args: args3, scheduled_at: {days_after(12), delta: 10}],
      100
    )

    vars4 = %{name: context.user.username, expire_at: days_after(30) |> EmailJobs.format_date()}
    args4 = Map.merge(args, %{template: after_trial_annual_discount_template(), vars: vars4})

    assert_enqueued(
      [worker: Sanbase.Mailer, args: args4, scheduled_at: {days_after(24), delta: 10}],
      100
    )
  end

  test "schedule emails on Sanbase PRO subscription started", context do
    query = subscribe_mutation(context.plans.plan_pro_sanbase.id)

    execute_mutation(context.conn, query)

    args = %{
      user_id: context.user.id,
      template: pro_subscription_stared_template(),
      vars: %{
        name: context.user.username,
        subscription_type: "Sanbase PRO",
        subscription_duration: "month"
      }
    }

    assert_enqueued([worker: Sanbase.Mailer, args: args], 100)
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
