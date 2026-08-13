defmodule SanbaseWeb.Admin.PromoTrialLive.IndexTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  setup context do
    admin = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(admin.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(admin)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    user = insert(:user, email: "promo-user@example.com", stripe_customer_id: "cus_test_promo")
    plan = context.plans.plan_pro_sanbase

    subscription =
      insert(:subscription,
        user: user,
        plan: plan,
        stripe_id: "sub_promo_live",
        status: "trialing",
        trial_end: Timex.shift(Timex.now(), days: 14) |> DateTime.truncate(:second)
      )

    granted_at = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    promo_trial =
      Repo.insert!(%PromoTrial{
        user_id: user.id,
        trial_days: 14,
        plans: ["Sanbase by Santiment / PRO (month)"],
        subscription_ids: [subscription.id],
        inserted_at: granted_at,
        updated_at: granted_at
      })

    {:ok, conn: conn, user: user, subscription: subscription, promo_trial: promo_trial}
  end

  test "lists promo trials with their subscriptions", context do
    {:ok, _view, html} = live(context.conn, "/admin/promo_trials")

    assert html =~ "promo-user@example.com"
    assert html =~ "sub_promo_live"
    assert html =~ "14 days"
  end

  test "extending the trial days propagates to Stripe", context do
    test_pid = self()

    with_mock StripeApi, [:passthrough],
      update_subscription: fn stripe_id, params ->
        send(test_pid, {:stripe_update_subscription, stripe_id, params})
        StripeApiTestResponse.update_subscription_resp(status: "trialing")
      end do
      {:ok, view, _html} = live(context.conn, "/admin/promo_trials")

      view
      |> element("button[phx-click='edit_days'][phx-value-id='#{context.promo_trial.id}']")
      |> render_click()

      view
      |> element("button[phx-click='shift_days'][phx-value-days='30']")
      |> render_click()

      view
      |> element("button[phx-click='save_days'][phx-value-id='#{context.promo_trial.id}']")
      |> render_click()

      assert_receive {:stripe_update_subscription, "sub_promo_live", params}
      assert Repo.get(PromoTrial, context.promo_trial.id).trial_days == 44
      assert params.cancel_at == params.trial_end - 60
    end
  end

  test "cancelling all subscriptions of a promo trial propagates to Stripe", context do
    test_pid = self()

    with_mock StripeApi, [:passthrough],
      cancel_subscription_immediately: fn stripe_id, _params ->
        send(test_pid, {:stripe_cancel, stripe_id})
        StripeApiTestResponse.cancel_subscription_immediately_resp(stripe_id: stripe_id)
      end do
      {:ok, view, _html} = live(context.conn, "/admin/promo_trials")

      view
      |> element(
        "button[phx-click='confirm_cancel_all'][phx-value-id='#{context.promo_trial.id}']"
      )
      |> render_click()

      view |> element("button[phx-click='do_confirmed']") |> render_click()

      assert_receive {:stripe_cancel, "sub_promo_live"}
      assert Repo.get(Subscription, context.subscription.id).status == :canceled
    end
  end

  test "searching filters the listed promo trials", context do
    {:ok, view, _html} = live(context.conn, "/admin/promo_trials")

    html = view |> element("input[phx-keyup='search']") |> render_keyup(%{"value" => "nobody"})

    refute html =~ "promo-user@example.com"
    assert html =~ "No promo trials match."
  end
end
