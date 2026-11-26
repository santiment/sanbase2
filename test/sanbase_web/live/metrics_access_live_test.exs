defmodule SanbaseWeb.MetricsAccessLiveTest do
  @moduledoc """
  The public metrics-by-plan page. Rows come from the seeded test DB through
  `PlanMetricAccess.rows/0` (uncached in the test env); a fixture category holds
  the metrics the tests look at, so they render on the first page whatever the
  seed's taxonomy order is.
  """
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sanbase.Billing.Plan.PlanMetricAccess
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.MetricGroup

  @price_module "Sanbase.Price.MetricAdapter"
  @registry_module "Sanbase.Clickhouse.MetricAdapter"
  @category_name "Access Test Market"
  @category_slug "access-test-market"
  @page_size 150

  setup do
    {:ok, category} = MetricCategory.create(%{name: @category_name, display_order: 1})

    {:ok, pricing} =
      MetricGroup.create(%{name: "Pricing", category_id: category.id, display_order: 1})

    {:ok, valuation} =
      MetricGroup.create(%{name: "Valuation", category_id: category.id, display_order: 2})

    map_metric("price_usd", category, pricing, @price_module)
    map_metric("mvrv_usd", category, valuation, @registry_module)
    # Seeded with min plan SANAPI "pro", SANBASE "free".
    map_metric("aave_v2_action_deposits", category, valuation, @registry_module)

    rows = PlanMetricAccess.rows()

    %{
      price_row: dom_id(row_for(rows, "price_usd")),
      mvrv_row: dom_id(row_for(rows, "mvrv_usd")),
      volume_row: dom_id(row_for(rows, "volume_usd")),
      aave_row: dom_id(row_for(rows, "aave_v2_action_deposits"))
    }
  end

  test "renders for an anonymous visitor with Free selected by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/metrics_access")

    assert has_element?(view, "#plan-free[aria-current=true]")
    refute has_element?(view, "#plan-sanbase_pro[aria-current=true]")
    assert has_element?(view, "#plan-picker")
    assert has_element?(view, "#plan-summary")
    assert has_element?(view, "#metrics-access-filters #metric-search")
    assert has_element?(view, "#metrics-access-filters #category-select #category-all")
    assert has_element?(view, "#metric-rows[phx-update=stream]")
    refute has_element?(view, "#metric-empty")
    # Category and group are columns, not heading rows.
    refute has_element?(view, "#metric-rows [data-kind=header]")
    refute has_element?(view, "h3")
  end

  test "switching plan patches the URL and updates the cells", %{conn: conn, mvrv_row: mvrv} do
    {:ok, view, _html} = live(conn, ~p"/metrics_access?category=#{@category_slug}")

    assert text(view, "##{mvrv}-api") == "Last year · 30-day delay"

    view |> element("#plan-business_pro") |> render_click()
    assert_patch(view, "/metrics_access?plan=business_pro&category=#{@category_slug}")

    assert has_element?(view, "#plan-business_pro[aria-current=true]")
    assert text(view, "##{mvrv}-api") == "Last 2 years · Realtime"
    assert text(view, "#headline-api") =~ "Last 2 years · Realtime"
  end

  test "dates=exact shows resolved dates", %{conn: conn, mvrv_row: mvrv} do
    {:ok, view, _html} =
      live(conn, ~p"/metrics_access?plan=business_pro&category=#{@category_slug}")

    view |> element("#dates-exact") |> render_click()
    assert_patch(view, "/metrics_access?plan=business_pro&category=#{@category_slug}&dates=exact")

    since = "Since " <> Date.to_iso8601(Date.add(Date.utc_today(), -730))
    assert text(view, "##{mvrv}-api") == since <> " · Realtime"

    view |> element("#dates-relative") |> render_click()
    assert_patch(view, "/metrics_access?plan=business_pro&category=#{@category_slug}")
    assert text(view, "##{mvrv}-api") =~ "Last 2 years"
  end

  test "category filter shows only that category, with category and group columns", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access")

    change(view, %{"category" => @category_slug})
    assert_patch(view, "/metrics_access?category=#{@category_slug}")

    assert has_element?(view, "##{ctx.price_row}")
    assert has_element?(view, "##{ctx.mvrv_row}")
    refute has_element?(view, "##{ctx.volume_row}")
    assert has_element?(view, "#category-select #category-#{@category_slug}[selected]")
    assert text(view, "##{ctx.price_row}") =~ "Pricing"
    assert text(view, "##{ctx.mvrv_row}") =~ "Valuation"
    assert text(view, "##{ctx.mvrv_row}") =~ @category_name

    change(view, %{"category" => "all"})
    assert_patch(view, "/metrics_access")
    assert has_element?(view, "#category-select #category-all[selected]")
  end

  test "search matches display and technical names, case-insensitive", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access")

    # Technical name.
    change(view, %{"q" => "PRICE_USD"})
    assert_patch(view, "/metrics_access?q=PRICE_USD")
    assert has_element?(view, "##{ctx.price_row}")
    refute has_element?(view, "##{ctx.mvrv_row}")

    # Display name ("Price in USD"), not a substring of the technical name.
    change(view, %{"q" => "price IN usd"})
    assert has_element?(view, "##{ctx.price_row}")
    refute has_element?(view, "##{ctx.volume_row}")

    # The category counts follow the search.
    assert text(view, "#category-#{@category_slug}") == "#{@category_name} (1)"
  end

  test "regex characters in search do not crash and show the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/metrics_access")

    change(view, %{"q" => "(*["})

    assert has_element?(view, "#metric-empty")
    refute has_element?(view, "#metric-rows [data-kind=row]")

    {:ok, view, _html} = live(conn, ~p"/metrics_access?q=.*")
    assert has_element?(view, "#metric-empty")
  end

  test "bogus params fall back to defaults", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=bogus&category=nope&dates=foo")

    assert has_element?(view, "#plan-free[aria-current=true]")
    assert has_element?(view, "#category-select #category-all[selected]")
    assert has_element?(view, "#dates-relative[aria-pressed=true]")
    assert has_element?(view, "#metric-rows [data-kind=row]")
  end

  test "a seeded Pro-on-API metric is locked on Free via the API, without mocks", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

    assert text(view, "##{ctx.aave_row}-api") == "Requires Sanbase Pro"
    assert has_element?(view, "##{ctx.aave_row}-api[data-locked]")
    refute has_element?(view, "##{ctx.aave_row}-sanbase[data-locked]")

    view |> element("#plan-sanbase_pro") |> render_click()
    refute has_element?(view, "##{ctx.aave_row}-api[data-locked]")
  end

  test "with no metrics at all and no search, the empty state does not quote a search", %{
    conn: conn
  } do
    mock(PlanMetricAccess, :rows, fn -> [] end)

    {:ok, view, _html} = live(conn, ~p"/metrics_access")

    assert has_element?(view, "#metric-empty")
    refute text(view, "#metric-empty") =~ "“"
    refute has_element?(view, "#clear-search")
  end

  test "a cell locked only in one channel does not mute the whole row", ctx do
    # Min plan "max" on the API, "free" in Sanbase. plan_has_access? reads the min
    # plan through a local call, so the check itself is mocked.
    mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
      {:metric, "mvrv_usd"}, "SANAPI", plan_name ->
        Sanbase.Billing.Plan.StandardAccessChecker.max_plan?("SANAPI", plan_name)

      query, product, plan_name ->
        :meck.passthrough([query, product, plan_name])
    end)

    {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

    assert text(view, "##{ctx.mvrv_row}-api") == "Requires Business Max"
    assert has_element?(view, "##{ctx.mvrv_row}-api[data-locked]")

    refute text(view, "##{ctx.mvrv_row}-sanbase") =~ "Requires"
    refute has_element?(view, "##{ctx.mvrv_row}-sanbase[data-locked]")
    refute has_element?(view, "##{ctx.mvrv_row}[data-locked]")

    # Locked in both channels mutes the whole row.
    :meck.expect(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
      {:metric, "mvrv_usd"}, _product, _plan_name -> false
      query, product, plan_name -> :meck.passthrough([query, product, plan_name])
    end)

    {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")
    assert has_element?(view, "##{ctx.mvrv_row}[data-locked]")
    assert text(view, "##{ctx.mvrv_row}-sanbase") == "Custom plan only"
  end

  describe "the summary" do
    test "names the plan that unlocks the locked metrics, per channel", %{conn: conn} do
      mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, "SANAPI", plan_name ->
          Sanbase.Billing.Plan.StandardAccessChecker.max_plan?("SANAPI", plan_name)

        query, product, plan_name ->
          :meck.passthrough([query, product, plan_name])
      end)

      expected = locked_count(PlanMetricAccess.rows(), "free", :api, "business_max")
      assert expected >= 1

      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      assert text(view, "#summary-api-locked-business_max") =~
               ~r/\b#{expected} needs? Business Max/
    end

    test "counts metrics no plan unlocks apart from those a higher plan unlocks", %{
      conn: conn
    } do
      mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, _product, _plan_name -> false
        query, product, plan_name -> :meck.passthrough([query, product, plan_name])
      end)

      rows = PlanMetricAccess.rows()
      custom = locked_count(rows, "business_max", :api, nil)
      assert custom >= 1

      {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_max")

      assert text(view, "#summary-api-locked-custom") =~ "#{custom} custom plan only"
      refute text(view, "#summary-api") =~ "need"

      included = Enum.count(rows, &(not match?({:locked, _}, &1.access[{"business_max", :api}])))
      # The number and "of N" are separate flex items, so textContent has no space.
      assert text(view, "#summary-api") =~ ~r/Included via API\s*#{included}\s*of #{length(rows)}/
    end
  end

  test "Business plans say which Sanbase plan they include", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_pro")
    assert text(view, "#headline-sanbase") =~ "Includes Sanbase Pro"
    assert has_element?(view, "#plan-business_pro[title='Includes Sanbase Pro']")

    {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_max")
    assert text(view, "#headline-sanbase") =~ "Includes Sanbase Max"

    {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=sanbase_max")
    refute text(view, "#headline-sanbase") =~ "Includes"
  end

  test "only the first page renders, Show more appends the next", %{conn: conn} do
    total = length(PlanMetricAccess.rows())
    assert total > @page_size, "the seeded test DB must hold more rows than one page"

    {:ok, view, _html} = live(conn, ~p"/metrics_access")

    assert row_ids(view) |> length() == @page_size
    assert has_element?(view, "#show-more")
    # Rows load on scroll through a hook on the Show more bar, watched against the
    # window viewport; the table's horizontal scroller never scrolls vertically.
    assert has_element?(view, "#load-more[phx-hook=LoadMoreOnVisible] #show-more")
    refute has_element?(view, "[phx-viewport-bottom]")

    view |> element("#show-more") |> render_click()

    ids = row_ids(view)
    assert length(ids) == min(2 * @page_size, total)
    assert Enum.uniq(ids) == ids

    # Load the rest: the button goes away once everything is on the page.
    Enum.each(1..div(total, @page_size), fn _ ->
      if has_element?(view, "#show-more"), do: view |> element("#show-more") |> render_click()
    end)

    assert row_ids(view) |> length() == total
    refute has_element?(view, "#show-more")
    refute has_element?(view, "#load-more")
  end

  test "a plan switch keeps the loaded rows, a new search starts from one page", %{conn: conn} do
    # "_" is in nearly every technical name, so the search spans several pages.
    q = "_"
    matching = Enum.count(PlanMetricAccess.rows(), &Enum.any?(&1.metrics, fn m -> m =~ q end))
    assert matching > 2 * @page_size

    {:ok, view, _html} = live(conn, ~p"/metrics_access")
    view |> element("#show-more") |> render_click()
    assert length(row_ids(view)) == 2 * @page_size

    view |> element("#plan-business_pro") |> render_click()
    assert_patch(view, "/metrics_access?plan=business_pro")
    assert length(row_ids(view)) == 2 * @page_size

    change(view, %{"q" => q})
    assert_patch(view, "/metrics_access?plan=business_pro&q=_")
    assert length(row_ids(view)) == @page_size
  end

  test "search on a variant name shows that variant inline", %{conn: conn} do
    variant = "mvrv_usd_30d"
    row = row_for(PlanMetricAccess.rows(), variant)
    assert row && length(row.metrics) > 1, "#{variant} must be a collapsed template variant"

    {:ok, view, _html} = live(conn, ~p"/metrics_access")
    change(view, %{"q" => variant})

    assert text(view, "##{dom_id(row)}-matched") =~ variant
  end

  defp change(view, params) do
    view |> element("#metrics-access-filters") |> render_change(params)
  end

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#metric-rows [data-kind=row]")
    |> LazyHTML.attribute("id")
  end

  defp locked_count(rows, plan, channel, unlocking_plan) do
    Enum.count(rows, &(&1.access[{plan, channel}] == {:locked, unlocking_plan}))
  end

  defp row_for(rows, metric), do: Enum.find(rows, &(metric in &1.metrics))

  defp dom_id(%{id: id}), do: "metric-" <> id

  defp map_metric(metric, category, group, module) do
    {:ok, _} =
      MetricCategoryMapping.create(%{
        module: module,
        metric: metric,
        category_id: category.id,
        group_id: group.id,
        display_order: 1
      })
  end

  defp mock(mod, fun, impl) do
    :meck.new(mod, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(mod) end)
    :meck.expect(mod, fun, impl)
  end
end
