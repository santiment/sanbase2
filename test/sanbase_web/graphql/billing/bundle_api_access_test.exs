defmodule Sanbase.Billing.BundleApiAccessTest do
  @moduledoc ~s"""
  Bundle access over a **real GraphQL request**, authenticated with a real API
  key, through the whole plug pipeline.

  ## Why this exists separately from the unit tests

  The unit tests hand an entitlement directly to the access checker, so they prove
  the decision logic. They cannot prove the step before it: that a live request
  digs the entitlement out of its context and passes it along. If that plumbing
  broke, every unit test would still pass while every real request from a paying
  customer failed.

  This test is the one that would catch it. It asserts on refusal *messages* and
  returned data, not on internal calls, so it stays honest about what a customer
  would actually see.

  ## The scenarios are derived from the packages

  `@packaged_metrics` says which metric belongs to which package, and every test
  works out its expectations from the packages the subscription bought. A
  social+development customer must reach the social and development metrics and be
  refused the market and onchain ones - and the test says so by construction
  rather than by a hand-maintained list.
  """

  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  @moduletag capture_log: true

  # One real metric per package. Real, because the resolver refuses metrics that
  # do not exist and this test would then pass for the wrong reason.
  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup_all_with_mocks([
    {Sanbase.Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]},
    {Sanbase.SocialData.TrendingWords, [:passthrough],
     [get_trending_words: fn _, _, _, _, _, _ -> trending_words_resp() end]}
  ]) do
    []
  end

  setup context do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

    bundle_plan =
      insert(:plan_pro,
        id: 9500,
        name: "BUNDLE",
        product_id: context.product_api.id,
        amount: 0,
        stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
      )

    project = insert(:random_erc20_project)

    publish_snapshot()

    %{bundle_plan: bundle_plan, project: project}
  end

  describe "a bundle subscriber over the API" do
    setup context do
      subscribe(context.bundle_plan, ["social", "development"])
    end

    test "reaches a metric from a package it bought", context do
      %{conn: conn, project: project} = context

      result = get_metric(conn, @packaged_metrics["social"], project.slug)

      assert result["data"]["getMetric"]["timeseriesData"] != nil
      refute Map.has_key?(result, "errors")
    end

    test "reaches every metric from every package it bought", context do
      %{conn: conn, project: project, packages: packages} = context

      for slug <- packages do
        metric = @packaged_metrics[slug]
        result = get_metric(conn, metric, project.slug)

        refute Map.has_key?(result, "errors"),
               "#{metric} (#{slug}) was refused but #{slug} was bought: #{inspect(result["errors"])}"
      end
    end

    test "is refused every metric from every package it did not buy", context do
      %{conn: conn, project: project, packages: packages} = context

      not_bought = Map.keys(@packaged_metrics) -- packages
      assert not_bought != [], "the scenario is pointless if everything was bought"

      for slug <- not_bought do
        metric = @packaged_metrics[slug]
        result = get_metric(conn, metric, project.slug)

        assert Map.has_key?(result, "errors"),
               "#{metric} (#{slug}) was allowed but #{slug} was not bought"
      end
    end

    test "the refusal explains itself rather than surfacing an internal error", context do
      %{conn: conn, project: project} = context

      result = get_metric(conn, @packaged_metrics["market"], project.slug)

      message = result["errors"] |> hd() |> Map.get("message")

      # A MissingEntitlementError or CaseClauseError leaking to the customer would
      # show up here as a generic 500-ish message instead.
      assert message =~ "price_usd"
      refute message =~ "MissingEntitlement"
      refute message =~ "NotImplemented"
    end

    test "queries stay reachable, as they are for everyone today", context do
      %{conn: conn} = context

      result =
        execute(conn, """
        {
          getTrendingWords(size: 1, from: "utc_now-7d", to: "utc_now", interval: "1d") {
            datetime
          }
        }
        """)

      refute Map.has_key?(result, "errors")
    end
  end

  describe "the same plan name, two different customers" do
    test "get different answers on a real request", context do
      %{bundle_plan: plan, project: project} = context

      social = subscribe(plan, ["social"])
      market = subscribe(plan, ["market"])

      social_metric = @packaged_metrics["social"]
      market_metric = @packaged_metrics["market"]

      refute Map.has_key?(get_metric(social.conn, social_metric, project.slug), "errors")
      assert Map.has_key?(get_metric(social.conn, market_metric, project.slug), "errors")

      assert Map.has_key?(get_metric(market.conn, social_metric, project.slug), "errors")
      refute Map.has_key?(get_metric(market.conn, market_metric, project.slug), "errors")
    end
  end

  describe "a bundle subscriber without a Sanbase subscription" do
    setup context do
      subscribe(context.bundle_plan, ["social"])
    end

    test "is treated as the equivalent standard plan on Sanbase, not as a bundle", context do
      # Product's answer to Q5: the same as a SanAPI PRO customer with no Sanbase
      # subscription. So the bundle name must never reach a Sanbase access check -
      # if it did, the package metric list would decide Sanbase access, and the
      # Sanbase-specific limits have no per-package answer.
      %{user: user} = context

      subscription = Subscription.current_subscription(user.id, context.product_api.id)

      assert Sanbase.Billing.Plan.plan_name(subscription.plan) == "BUNDLE"

      # These four are the Sanbase-side limits. Before Q5 was answered every one
      # of them raised for a bundle, so a bundle customer opening Sanbase got a
      # 500.
      equivalent = Bundle.equivalent_standard_plan()

      assert Sanbase.Billing.Plan.SanbaseAccessChecker.alerts_limit("BUNDLE") ==
               Sanbase.Billing.Plan.SanbaseAccessChecker.alerts_limit(equivalent)

      for product <- ["SANAPI", "SANBASE"] do
        assert Sanbase.Queries.Authorization.credits_limit(product, "BUNDLE") ==
                 Sanbase.Queries.Authorization.credits_limit(product, equivalent)

        assert Sanbase.Queries.Authorization.query_executions_limit(product, "BUNDLE") ==
                 Sanbase.Queries.Authorization.query_executions_limit(product, equivalent)

        assert Sanbase.Queries.Authorization.user_plan_to_dynamic_repo(product, "BUNDLE") ==
                 Sanbase.Queries.Authorization.user_plan_to_dynamic_repo(product, equivalent)
      end
    end
  end

  describe "a bundle subscription whose entitlement was never resolved" do
    test "raises rather than quietly granting free-tier access", context do
      %{bundle_plan: plan, project: project} = context

      user = insert(:user)

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: plan.id,
        status: :active,
        stripe_id: "sub_" <> Ecto.UUID.generate()
      )

      {:ok, apikey} = Apikey.generate_apikey(user)
      conn = setup_apikey_auth(build_conn(), apikey)

      # This is the documented behavior, and the alternative is worse: answering
      # from the standard ladder would give a paying customer roughly free-tier
      # access with no error anywhere (§7.5 B1). The cost is that the customer sees
      # a 500 rather than an explanation - see the note in §5.8 about whether this
      # should become a friendly GraphQL error instead.
      assert_raise Bundle.MissingEntitlementError, fn ->
        get_metric(conn, @packaged_metrics["social"], project.slug)
      end
    end
  end

  describe "asking for a bundle's restrictions by name" do
    test "is refused rather than raising", context do
      # getAccessRestrictions takes `plan` as a free-form string on a query marked
      # access: :free, and "BUNDLE" became an existing plan name the moment the
      # marker rows were added. Without the guard, any unauthenticated caller could
      # reach the bundle access path with no entitlement and turn a deliberate
      # MissingEntitlementError into a 500.
      %{conn: conn} = context

      result =
        execute(conn, """
        {
          getAccessRestrictions(planName: "BUNDLE", product: SANAPI) { name }
        }
        """)

      assert Map.has_key?(result, "errors")
      assert result["errors"] |> hd() |> Map.get("message") =~ "BUNDLE"
    end

    test "still works for a standard plan", context do
      %{conn: conn} = context

      result =
        execute(conn, """
        {
          getAccessRestrictions(planName: "PRO", product: SANAPI) { name }
        }
        """)

      refute Map.has_key?(result, "errors")
    end
  end

  describe "the API call quota" do
    test "is not reached by a santiment.net user, which is why the tests above pass", context do
      # Worth stating outright: the factory's default email is @santiment.net, and
      # those users are exempt from quota (`user_has_limits?/1`). Every test above
      # therefore proves access without touching the quota path. Without this note
      # the suite would look like it covered both.
      %{bundle_plan: plan, project: project} = context

      %{conn: conn} = subscribe(plan, ["social"])

      refute Map.has_key?(get_metric(conn, @packaged_metrics["social"], project.slug), "errors")
    end

    test "raises for a customer who is subject to it", context do
      # The quota check runs on every API request, and the bundle branch of
      # plan_to_api_call_limits deliberately refuses: the numbers live on the
      # api_call_limits row and nothing writes them there yet. So a real paying
      # bundle customer cannot be served at all until that sync exists (task WH).
      #
      # Pinned as a raise rather than left untested, so that implementing the sync
      # turns this test red and it gets updated to assert the served response.
      %{bundle_plan: plan, project: project} = context

      %{conn: conn} = subscribe(plan, ["social"], email: "bundle-customer@example.com")

      assert_raise Bundle.NotImplementedError, fn ->
        get_metric(conn, @packaged_metrics["social"], project.slug)
      end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp subscribe(plan, packages, opts \\ []) do
    user =
      case Keyword.get(opts, :email) do
        nil -> insert(:user)
        email -> insert(:user, email: email)
      end

    subscription =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: plan.id,
        status: :active,
        stripe_id: "sub_" <> Ecto.UUID.generate()
      )

    for slug <- packages do
      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: slug, type: :package})
    end

    {:ok, _} = Resolver.sync(subscription.id)

    {:ok, apikey} = Apikey.generate_apikey(user)

    %{
      user: user,
      subscription: subscription,
      packages: packages,
      apikey: apikey,
      conn: setup_apikey_auth(build_conn(), apikey)
    }
  end

  defp publish_snapshot do
    for {package, index} <- Enum.with_index(Bundle.Package.all()) do
      {:ok, category} =
        MetricCategory.create(%{name: package.category, display_order: index})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Metric.BundleTestAdapter",
          metric: Map.fetch!(@packaged_metrics, package.slug),
          category_id: category.id
        })
    end

    {:ok, snapshot} = PackageSnapshot.publish(notes: "test")
    snapshot
  end

  defp get_metric(conn, metric, slug) do
    execute(conn, """
    {
      getMetric(metric: "#{metric}") {
        timeseriesData(slug: "#{slug}", from: "utc_now-7d", to: "utc_now", interval: "1d") {
          datetime
          value
        }
      }
    }
    """)
  end

  defp execute(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp trending_words_resp do
    {:ok, %{~U[2026-08-01 00:00:00Z] => [%{word: "btc", score: 1.0}]}}
  end

  defp metric_resp do
    {:ok,
     [
       %{datetime: ~U[2026-08-01 00:00:00Z], value: 10.0},
       %{datetime: ~U[2026-08-02 00:00:00Z], value: 20.0}
     ]}
  end
end
