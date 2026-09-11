defmodule SanbaseWeb.Admin.SubscriptionGrantsLiveTest do
  @moduledoc ~s"""
  The screen sales uses to apply an add-on it already sold and invoiced
  separately. See §8 task **GR** of `docs/composable-api-plans-handover.md`.

  What is asserted here is what would make the screen dangerous rather than
  merely broken: that applying a grant actually reaches the quota path, that
  removing one puts the customer back exactly where they were, and that the page
  says out loud that it does not charge anybody.
  """

  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole
  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Subscription
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup context do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9601")

    institutional_plan =
      insert(:plan_pro,
        id: 9600,
        name: "INSTITUTIONAL",
        interval: "year",
        product_id: context.product_api.id,
        amount: 958_800,
        stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
      )

    categorize_metrics()
    {:ok, _snapshot} = PackageSnapshot.publish(notes: "test")

    admin = insert(:user, email: "admin#{System.unique_integer([:positive])}@santiment.net")
    role = insert(:role_admin_panel_owner)
    {:ok, _} = UserRole.create(admin.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(admin)

    customer = insert(:user, email: "customer#{System.unique_integer([:positive])}@example.com")

    subscription =
      insert(:subscription_pro,
        user_id: customer.id,
        plan_id: institutional_plan.id,
        status: :active,
        stripe_id: "sub_inst_" <> Ecto.UUID.generate()
      )

    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    %{conn: conn, admin: admin, customer: customer, subscription: subscription}
  end

  test "says plainly that it moves entitlement and not money", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/subscription_grants")

    assert html =~ "Subscription grants"
    assert html =~ "entitlement, not money"
  end

  test "applying a grant reaches the quota path", context do
    %{conn: conn, customer: customer} = context

    view = select_customer(conn, customer)

    html = submit_grant(view, %{"extra_api_calls" => "0", "note" => ""})

    # An empty form is the refusal to store a grant that grants nothing rather than a
    # silent no-op. The field path is asserted because a grant is an embed: its errors
    # nest one level down, and a flat join would show the admin the raw inner map
    # instead of a sentence.
    assert html =~ "grant.extra_api_calls_per_month: a grant must add extra API calls"

    submit_grant(view, %{"extra_api_calls" => "200000", "note" => "INV-1"})

    grant = customer |> subscription_of() |> Subscription.grant()
    assert grant.extra_api_calls_per_month == 200_000
    assert grant.note == "INV-1"

    # The daily reconciler matches on plan name and would never notice a grant, so
    # the screen has to push the new allowance itself.
    acl = Repo.get_by!(ApiCallLimit, user_id: customer.id)
    plan_month = ApiCallLimit.plan_to_api_call_limits("sanapi_institutional").month
    assert acl.resolved_api_call_limits["month"] == plan_month + 200_000
  end

  test "granting a package stores the metrics it expanded to", context do
    %{conn: conn, customer: customer} = context

    view = select_customer(conn, customer)

    view |> element("button[phx-value-slug=market]") |> render_click()
    submit_grant(view, %{"extra_api_calls" => "0", "note" => "INV-2"})

    grant = customer |> subscription_of() |> Subscription.grant()

    assert grant.full_history_packages == ["market"]
    assert @packaged_metrics["market"] in grant.full_history_metrics
    refute @packaged_metrics["social"] in grant.full_history_metrics
  end

  test "removing a grant puts the customer back on the plan", context do
    %{conn: conn, customer: customer} = context

    view = select_customer(conn, customer)

    submit_grant(view, %{"extra_api_calls" => "200000", "note" => "INV-3"})

    view |> element("button[phx-click=revoke]") |> render_click()

    assert customer |> subscription_of() |> Subscription.grant() == nil

    acl = Repo.get_by!(ApiCallLimit, user_id: customer.id)
    assert acl.resolved_api_call_limits == nil
  end

  test "a value typed and submitted before the debounce fires is the one granted", context do
    %{conn: conn, customer: customer} = context

    view = select_customer(conn, customer)

    # No set_extra_calls / set_note hook first: the inputs are debounced, so this is a
    # form submitted inside the debounce window. Read from the assigns instead of the
    # submitted params, this would grant 0 calls and refuse for a missing note.
    submit_grant(view, %{"extra_api_calls" => "125000", "note" => "INV-typed-fast"})

    grant = customer |> subscription_of() |> Subscription.grant()

    assert grant.extra_api_calls_per_month == 125_000
    assert grant.note == "INV-typed-fast"
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp submit_grant(view, params) do
    view |> form("form[phx-submit=apply_grant]", params) |> render_submit()
  end

  defp select_customer(conn, customer) do
    {:ok, view, _html} = live(conn, "/admin/subscription_grants")

    view |> render_hook("search_user", %{"value" => customer.email})
    view |> render_hook("select_user", %{"id" => to_string(customer.id)})
    view |> element("button[phx-click=select_subscription]") |> render_click()

    view
  end

  defp subscription_of(customer) do
    Repo.get_by!(Subscription, user_id: customer.id)
  end

  defp categorize_metrics do
    Sanbase.Billing.Plan.Bundle.Package.all()
    |> Enum.with_index()
    |> Enum.each(fn {package, index} ->
      {:ok, category} =
        MetricCategory.create(%{name: package.category, display_order: index})

      # Mapped by module/metric rather than through the registry: this case does not
      # seed the registry, and what the snapshot needs is the metric name.
      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Metric.SubscriptionGrantsTestAdapter",
          metric: Map.fetch!(@packaged_metrics, package.slug),
          category_id: category.id
        })
    end)
  end
end
