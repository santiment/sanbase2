defmodule Sanbase.EmailTest do
  use SanbaseWeb.ConnCase
  use Oban.Testing, repo: Sanbase.Repo

  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.Email.Template
  import Sanbase.DateTimeUtils, only: [days_after: 1]

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias Sanbase.Billing.Subscription

  setup do
    not_registered_user = insert(:user, email: "example@santiment.net", is_registered: false)
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, not_registered_user: not_registered_user}
  end

  test "schedule emails on user registration", context do
    {:ok, user} = context.not_registered_user |> User.update_email_token()

    res = execute_mutation(build_conn(), email_login_verify_mutation(user))

    args = %{
      user_id: context.not_registered_user.id,
      vars: %{name: context.not_registered_user.username}
    }

    Process.whereis(Sanbase.EventBus.UserEventsSubscriber) |> :sys.get_state() |> IO.inspect()

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
    {:ok, subscription} =
      Subscription.create(%{
        stripe_id: "123",
        user_id: context.user.id,
        plan_id: 201,
        status: "trialing",
        trial_end: days_after(14)
      })

    args = %{
      user_id: context.user.id,
      vars: %{name: context.user.username, subscription_type: "Sanbase PRO"}
    }

    assert_enqueued(
      [worker: Sanbase.Mailer, args: Map.put(args, :template, trial_started_template())],
      500
    )

    # assert_enqueued [worker: Sanbase.Mailer, args: Map.put(args, :template, end_of_trial_template()), scheduled_at: {days_after(11), delta: 10}], 100
    # assert_enqueued [worker: Sanbase.Mailer, args: Map.put(args, :template, during_trial_annual_discount_template()), scheduled_at: {days_after(12), delta: 10}], 100
    # assert_enqueued [worker: Sanbase.Mailer, args: Map.put(args, :template, after_trial_annual_discount_template), scheduled_at: {days_after(24), delta: 10}], 100
  end

  test "schedule emails on Sanbase PRO subscription started" do
  end

  defp email_login_verify_mutation(user) do
    """
    mutation {
      emailLoginVerify(email: "#{user.email}", token: "#{user.email_token}") {
        user {
          email
          settings {
            newsletterSubscription
          }
        }
        token

      }
    }
    """
  end
end
