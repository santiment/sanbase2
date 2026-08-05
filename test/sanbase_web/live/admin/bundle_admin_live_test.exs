defmodule SanbaseWeb.Admin.BundleAdminLiveTest do
  @moduledoc ~s"""
  The two admin pages that make the bundle path visible: what each package
  contains, and what a given subscription actually grants.

  These are the pages an admin uses to answer "did this customer get what they
  paid for?", so the things asserted here are the things that would make the
  answer wrong or unobtainable: publishing writing a snapshot, creating a
  subscription resolving an entitlement, and the generated scenarios agreeing
  with the access checker.
  """

  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.SaleControls
  alias Sanbase.Billing.Subscription
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  # One real metric per package. Real, so a scenario that resolves to "allowed"
  # is allowed for the right reason.
  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup context do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

    bundle_plan =
      insert(:plan_pro,
        id: 9500,
        name: "BUNDLE",
        interval: "month",
        product_id: context.product_api.id,
        amount: 0,
        stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
      )

    categorize_metrics()

    admin = insert(:user, email: "admin#{System.unique_integer([:positive])}@santiment.net")
    role = insert(:role_admin_panel_owner)
    {:ok, _user_role} = UserRole.create(admin.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(admin)

    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    %{conn: conn, admin: admin, bundle_plan: bundle_plan}
  end

  describe "/admin/bundle_packages" do
    test "shows the live package contents before anything is published", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/bundle_packages")

      assert html =~ "Bundle Packages"
      assert html =~ "Bundle subscriptions cannot be resolved until one is published"

      # Every package's metric is pending, because the published baseline is empty.
      for metric <- Map.values(@packaged_metrics) do
        assert html =~ metric
      end
    end

    test "publishing writes a snapshot and clears the pending changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/bundle_packages")

      html =
        view
        |> form("form[phx-submit=publish]", %{"notes" => "first publish"})
        |> render_submit()

      assert html =~ "Published snapshot version 1"
      assert html =~ "The published snapshot matches the current categorization"

      snapshot = PackageSnapshot.latest()
      assert snapshot.version == 1
      assert snapshot.notes == "first publish"
    end

    test "publishing keeps notes typed but not blurred", %{conn: conn} do
      # The input only pushes to the socket on blur, so a note typed and submitted
      # with Enter has to be read from the submitted params or it is lost.
      {:ok, view, _html} = live(conn, "/admin/bundle_packages")

      view
      |> form("form[phx-submit=publish]", %{"notes" => "typed, never blurred"})
      |> render_submit()

      assert PackageSnapshot.latest().notes == "typed, never blurred"
    end
  end

  describe "/admin/bundle_subscriptions" do
    setup %{conn: conn} do
      {:ok, snapshot} = PackageSnapshot.publish(notes: "test")

      %{conn: conn, snapshot: snapshot}
    end

    test "renders and offers metric names for autocomplete", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/bundle_subscriptions")

      assert html =~ "Bundle Subscriptions"
      assert html =~ ~s(<datalist id="metric-names">)
      assert html =~ ~s(<datalist id="query-names">)
      assert html =~ ~s(<datalist id="signal-names">)

      # A name a generated scenario can produce has to be suggestable, otherwise
      # the autocomplete is misleading exactly where it is used.
      assert html =~ ~s(value="#{@packaged_metrics["social"]}")
      assert html =~ ~s(value="get_trending_words")
    end

    test "creating a subscription resolves an entitlement", %{conn: conn} do
      user = insert(:user, email: "customer#{System.unique_integer([:positive])}@example.com")

      {:ok, view, _html} = live(conn, "/admin/bundle_subscriptions")

      html = create_subscription(view, user, ["social", "development"])

      assert html =~ "Created a bundle subscription"
      assert html =~ "social, development" or html =~ "development, social"

      [subscription] = Subscription.list_bundle_subscriptions()
      entitlement = Subscription.bundle_entitlement(subscription)

      assert Enum.sort(entitlement.packages) == ["development", "social"]
      assert entitlement.package_snapshot_version == 1
    end

    test "generated scenarios all pass for the packages bought", %{conn: conn} do
      user = insert(:user, email: "customer#{System.unique_integer([:positive])}@example.com")

      {:ok, view, _html} = live(conn, "/admin/bundle_subscriptions")
      create_subscription(view, user, ["social", "development"])

      html = view |> element("button", "Run scenarios") |> render_click()

      # One row per package plus a query and an unknown metric, and no row may
      # disagree with its own expectation.
      assert html =~ "pass"
      refute html =~ "FAIL"

      for {slug, metric} <- @packaged_metrics do
        assert html =~ metric, "no scenario was generated for #{slug}"
      end
    end

    test "Inspect expands the scenario row and Hide closes it", %{conn: conn} do
      user = insert(:user, email: "customer#{System.unique_integer([:positive])}@example.com")

      {:ok, view, _html} = live(conn, "/admin/bundle_subscriptions")
      create_subscription(view, user, ["social"])
      view |> element("button", "Run scenarios") |> render_click()

      refute render(view) =~ "Also loaded into the Decide form above"

      html =
        view
        |> element(~s(button[phx-value-name="#{@packaged_metrics["social"]}"]))
        |> render_click()

      assert html =~ "Also loaded into the Decide form above"
      assert html =~ "SANAPI access"
      assert html =~ "Hide"

      html =
        view
        |> element(~s(button[phx-value-name="#{@packaged_metrics["social"]}"]))
        |> render_click()

      refute html =~ "Also loaded into the Decide form above"
    end

    test "canceling and deleting a subscription", %{conn: conn} do
      user = insert(:user, email: "customer#{System.unique_integer([:positive])}@example.com")

      {:ok, view, _html} = live(conn, "/admin/bundle_subscriptions")
      create_subscription(view, user, ["market"])

      html = view |> element("button", "Cancel") |> render_click()
      assert html =~ "Subscription canceled"

      [subscription] = Subscription.list_bundle_subscriptions()
      assert subscription.status == :canceled

      view |> element("button", "Delete") |> render_click()
      assert Subscription.list_bundle_subscriptions() == []
    end

    test "acting on a subscription deleted elsewhere says so instead of crashing", %{conn: conn} do
      user = insert(:user, email: "customer#{System.unique_integer([:positive])}@example.com")

      {:ok, view, _html} = live(conn, "/admin/bundle_subscriptions")
      create_subscription(view, user, ["market"])

      # The page can be left open while another tab deletes the row.
      [subscription] = Subscription.list_bundle_subscriptions()
      Repo.delete!(subscription)

      html = view |> element("button", "Cancel") |> render_click()

      assert html =~ "no longer exists"
    end
  end

  defp create_subscription(view, user, packages) do
    view |> element("input[phx-keyup=search_user]") |> render_keyup(%{"value" => user.email})
    view |> element(~s(a[phx-value-id="#{user.id}"])) |> render_click()

    for slug <- packages do
      view |> element(~s(button[phx-value-slug="#{slug}"])) |> render_click()
    end

    view |> element("button", "Create subscription") |> render_click()
  end

  describe "/admin/bundle_offering" do
    test "shows activate/deactivate controls for bundle and business plans", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/bundle_offering")

      assert has_element?(view, "#plan-sale-refresh")

      assert has_element?(view, "#bundle-plan-controls")
      assert has_element?(view, "#activate-bundle-plans")
      assert has_element?(view, "#deactivate-bundle-plans")

      assert has_element?(view, "#business-plan-controls")
      assert has_element?(view, "#activate-business-plans")
      assert has_element?(view, "#deactivate-business-plans")
    end

    test "the bundle buttons put the plans on and off sale", %{
      conn: conn,
      bundle_plan: bundle_plan
    } do
      # The starting position of the switch is written directly, because reaching
      # it through SaleControls would be using the thing under test to set up its
      # own test.
      bundle_plan |> Plan.changeset(%{is_private: true}) |> Repo.update!()

      {:ok, view, _html} = live(conn, "/admin/bundle_offering")

      assert bundle_section(view) =~ "DEACTIVATED"
      refute has_element?(view, "#activate-bundle-plans[disabled]")

      view |> element("#activate-bundle-plans") |> render_click()

      assert bundle_section(view) =~ "ACTIVE"
      assert SaleControls.bundle_plans_active?()

      # Only the move that changes something is offered, so an admin cannot
      # activate what is already active.
      assert has_element?(view, "#activate-bundle-plans[disabled]")
      refute has_element?(view, "#deactivate-bundle-plans[disabled]")

      view |> element("#deactivate-bundle-plans") |> render_click()

      assert bundle_section(view) =~ "DEACTIVATED"
      refute SaleControls.bundle_plans_active?()
      assert has_element?(view, "#deactivate-bundle-plans[disabled]")
    end

    test "the business buttons withdraw the plans from sale and bring them back",
         %{conn: conn} do
      bundle_active_before? = SaleControls.bundle_plans_active?()

      {:ok, view, _html} = live(conn, "/admin/bundle_offering")

      # The seeded BUSINESS_PRO/BUSINESS_MAX rows are not deprecated, so these
      # plans start on sale.
      assert business_section(view) =~ "ACTIVE"
      refute has_element?(view, "#deactivate-business-plans[disabled]")

      view |> element("#deactivate-business-plans") |> render_click()

      assert business_section(view) =~ "DEACTIVATED"
      refute SaleControls.business_plans_active?()
      assert has_element?(view, "#deactivate-business-plans[disabled]")
      refute has_element?(view, "#activate-business-plans[disabled]")

      view |> element("#activate-business-plans") |> render_click()

      assert business_section(view) =~ "ACTIVE"
      assert SaleControls.business_plans_active?()
      assert has_element?(view, "#activate-business-plans[disabled]")

      # Two independent switches: the business buttons write `is_deprecated` and
      # must leave the bundle plans' `is_private` where it was.
      assert SaleControls.bundle_plans_active?() == bundle_active_before?
    end
  end

  # The status line is the page's own answer about what is on sale, so it is read
  # back from the rendered section rather than from the database.
  defp bundle_section(view), do: view |> element("#bundle-plan-controls") |> render()

  defp business_section(view), do: view |> element("#business-plan-controls") |> render()

  defp categorize_metrics do
    for {package, index} <- Enum.with_index(Package.all()) do
      {:ok, category} = MetricCategory.create(%{name: package.category, display_order: index})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Metric.BundleAdminTestAdapter",
          metric: Map.fetch!(@packaged_metrics, package.slug),
          category_id: category.id
        })
    end
  end
end
