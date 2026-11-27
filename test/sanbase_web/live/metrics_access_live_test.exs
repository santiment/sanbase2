defmodule SanbaseWeb.MetricsAccessLiveTest do
  @moduledoc """
  The public metrics-by-plan page. Rows come from the seeded test DB through
  `PlanMetricAccess.rows/0` (cached in a :persistent_term, expired in setup and
  after each mock, see mock/3); a fixture category holds
  the metrics the tests look at, so they render on the first page whatever the
  seed's taxonomy order is.

  On the seeded data, in the fixture category:
    * price_usd - not restricted: all history, no delay everywhere
    * mvrv_usd - restricted: Free gets the last 1 year with a 30-day delay via the
      API, the last 2 years with a 30-day delay in Sanbase
    * aave_v2_action_deposits - restricted, min plan SANAPI "pro", SANBASE "free":
      locked on Free via the API only
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

    # The rows are cached in a :persistent_term that outlives each test: rebuild
    # them from this test's data (and again after any mock, see mock/3).
    PlanMetricAccess.expire_cache!()
    on_exit(&PlanMetricAccess.expire_cache!/0)

    rows = PlanMetricAccess.rows()

    %{
      price_row: dom_id(row_for(rows, "price_usd")),
      mvrv_row: dom_id(row_for(rows, "mvrv_usd")),
      volume_row: dom_id(row_for(rows, "volume_usd")),
      aave_row: dom_id(row_for(rows, "aave_v2_action_deposits"))
    }
  end

  describe "plan view" do
    test "renders for an anonymous visitor with Free selected by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      assert has_element?(view, "#plan-free[aria-current=true]")
      refute has_element?(view, "#view-compare[aria-current=true]")
      refute has_element?(view, "#plan-sanbase_pro[aria-current=true]")
      assert has_element?(view, "#plan-picker")
      assert has_element?(view, "#plan-summary")
      assert has_element?(view, "#plan-table")
      refute has_element?(view, "#compare-table")
      assert has_element?(view, "#metrics-access-filters #metric-search")
      assert has_element?(view, "#metrics-access-filters #category-select #category-all")
      assert has_element?(view, "#metrics-access-filters #access-select")
      refute has_element?(view, "#sort-select")
      # Category order is the default sort.
      # The default (taxonomy) order: no column is the sort.
      refute has_element?(view, "#plan-table [aria-sort]")
      refute has_element?(view, "#th-category")
      assert has_element?(view, "#show-locked[role=switch][aria-checked=false]")
      assert has_element?(view, "#variants-collapsed[aria-pressed=true]")
      # Dates: a two-option toggle, no visible prefix; the group keeps its name.
      assert has_element?(view, "#dates-switch[role=group][aria-label=Dates]")
      assert text(view, "#dates-switch") == "Relative dates Exact dates"
      assert has_element?(view, "#plan-metric-rows[phx-update=stream]")
      refute has_element?(view, "#compare-metric-rows")

      # One sticky bar: the five plans and Compare all plans, in one control.
      assert has_element?(view, "#plan-bar #plan-picker")

      options =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#plan-picker a")
        |> LazyHTML.attribute("id")

      assert options ==
               ~w(plan-free plan-sanbase_pro plan-sanbase_max plan-business_pro plan-business_max view-compare)

      # The plan view shows both channels: the channel control says so, display only.
      assert has_element?(view, "#plan-bar #channel-switch[data-mode=both]")
      assert has_element?(view, "#channel-sanbase")
      assert has_element?(view, "#channel-api")
      refute has_element?(view, "#channel-switch a")

      refute has_element?(view, "#metric-empty")
      # Category and group are columns, not heading rows.
      refute has_element?(view, "#plan-metric-rows [data-kind=header]")
      refute has_element?(view, "#plan-metric-rows h3")
    end

    test "an unrestricted metric shows all history and no delay, never a Free label", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      for channel <- ["sanbase", "api"] do
        cell = "##{ctx.price_row}-#{channel}"
        # The compact code under the bar; the full wording on hover and for readers.
        assert text(view, cell) == "Full"
        assert has_element?(view, "#{cell}[title='All history · No delay']")

        assert has_element?(
                 view,
                 "#{cell} [role=img][data-state=window][data-history=full][data-delay=none]"
               )

        assert has_element?(view, "#{cell} [role=img][aria-label='All history · No delay']")
      end

      refute text(view, "#plan-metric-rows") =~ "Free"
      refute render(view) =~ "For restricted metrics"
      refute render(view) =~ "Full history"
      refute render(view) =~ "Realtime"
    end

    test "the stats cards are the per-channel Included counts only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      assert has_element?(view, "#summary-sanbase")
      assert has_element?(view, "#summary-api")
      refute has_element?(view, "#headline-sanbase")
      refute has_element?(view, "#headline-api")
    end

    test "the bar halves carry the history and delay state", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      assert text(view, "##{ctx.mvrv_row}-api") == "1y · 30d"
      assert has_element?(view, "##{ctx.mvrv_row}-api[title='Last 1 year · 30-day delay']")

      assert has_element?(
               view,
               "##{ctx.mvrv_row}-api [role=img][data-history=limited][data-delay=delayed]"
             )

      assert has_element?(
               view,
               "##{ctx.mvrv_row}-api [role=img][aria-label='Last 1 year · 30-day delay']"
             )
    end

    test "the web app vs API note renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      # Seeded limits: Sanbase Pro's API access equals Free's.
      assert text(view, "#access-note [data-part=lead]") == "Web app and API access differ."

      # Seeded limits: Sanbase Pro's API window is limited and its call allowance
      # is below Business Pro's.
      assert text(view, "#access-note [data-part=web-app]") ==
               "Sanbase plans are built for the web app. Through the API, Sanbase Pro gives " <>
                 "only limited access: a shorter history, delayed data and a low API call " <>
                 "allowance, so it isn't suited for API use."

      assert text(view, "#access-note [data-part=api]") ==
               "Business plans are built for the API and also give access to the Sanbase web app."

      refute text(view, "#access-note") =~ "Sanbase Max"
    end

    test "the caption row keys the bars and opens a popover with the definitions", %{
      conn: conn
    } do
      for path <- ["/metrics_access", "/metrics_access?view=compare"] do
        {:ok, view, _html} = live(conn, path)

        # No separate legend card, no footnote: the sticky caption row does it.
        refute has_element?(view, "#bar-guide")
        refute has_element?(view, "#access-footnote")

        assert text(view, "thead #bar-key-label") == "Each bar: History · Delay"

        # One real cell per state: the same bar and aligned code as the table.
        for {state, code} <- [
              {"full", "Full"},
              {"limited", "2y · —"},
              {"both", "1y · 30d"},
              {"delayed", "All · 30d"},
              {"locked", "Locked"}
            ] do
          assert has_element?(view, "thead #bar-key [data-key=#{state}] [role=img]")
          assert text(view, "thead #bar-key [data-key=#{state}] [data-part=code]") == code
        end

        # The button toggles the popover (client-side JS), which starts closed.
        button = "thead #bar-help-button"
        assert has_element?(view, "#{button}[aria-expanded=false][aria-controls=bar-help]")
        assert has_element?(view, "#{button}[phx-click*=aria-expanded]")
        assert text(view, button) == "What do these mean?"
        assert has_element?(view, "#bar-help.hidden[role=dialog]")

        # Two sections: a heading, one sentence, then code chips with explanations.
        assert text(view, "#bar-help [data-term=history] h3") == "History — left half"

        assert text(view, "#bar-help [data-term=history] [data-part=definition]") ==
                 "How far back the data goes on this plan."

        assert text(view, "#bar-help [data-term=delay] h3") == "Delay — right half"

        assert text(view, "#bar-help [data-term=delay] [data-part=definition]") ==
                 "Whether the plan holds back the newest data."

        # Every example is a real cell: the same bar and aligned code as the table.
        two_years_ago = Date.add(Date.utc_today(), -730)
        since = Calendar.strftime(two_years_ago, "%b '%y")
        since_month = Calendar.strftime(two_years_ago, "%b %Y")

        for {term, examples} <- [
              # Only the half a section is about is coloured and labelled; the
              # other is grey with its code left blank ("All", not "Full").
              history: [
                {"full", "All", "all data since the metric started is accessible"},
                {"2y", "2y", "only the last 2 years are accessible; older data is not"},
                {"1y", "1y", "only the last 1 year is accessible; older data is not"},
                # The legend shows the month alone, so it stays under its half.
                {"exact", since,
                 "only data from #{since_month} on is accessible; older data is not"}
              ],
              delay: [
                {"none", "—",
                 "nothing held back: data up to the latest computed point is accessible"},
                {"delayed", "30d",
                 "the latest 30 days are not accessible; data ends 30 days before today"}
              ]
            ] do
          for {key, code, meaning} <- examples do
            row = "#bar-help [data-term=#{term}] [data-example='#{key}']"
            assert has_element?(view, "#{row} span[role=img].w-16[data-focus=#{term}]")
            # The other half: thin diagonal stripes, unlike a locked half's solid grey.
            assert has_element?(view, "#{row} span[role=img] > span[data-unfocused]")
            assert text(view, "#{row} [data-part=code]") == code
            # The blank half keeps its slot, so the code stays under its half.
            assert has_element?(view, "#{row} [data-part=code] > span[data-blank]")
            assert text(view, "#{row} [data-part=meaning]") == meaning
            # The bar says the same to screen readers and on hover.
            assert attribute(view, "#{row} span[role=img]", "aria-label") == meaning
          end

          # The heading's swatch is the same bar, with only its own half lit.
          assert has_element?(
                   view,
                   "#bar-help [data-term=#{term}] h3 span[role=img][data-focus=#{term}]"
                 )
        end

        # Side by side from md up, in a popover wide enough for it.
        assert has_element?(view, "#bar-help .md\\:grid-cols-2 [data-term=history]")
        assert has_element?(view, "#bar-help.w-\\[560px\\]")

        assert has_element?(view, "#bar-help [data-guide=locked] [role=img]")

        assert text(view, "#bar-help [data-part=computation]") ==
                 "No delay doesn't mean instant: each metric still has its normal " <>
                   "computation time, from minutes to a day."

        # Custom plans are not sold here.
        refute text(view, "#metrics-access") =~ "Custom"
        refute text(view, "#metrics-access") =~ "custom plan"
      end
    end

    test "switching plan patches the URL and updates the cells", %{conn: conn, mvrv_row: mvrv} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?category=#{@category_slug}")

      assert text(view, "##{mvrv}-api") == "1y · 30d"

      view |> element("#plan-business_pro") |> render_click()
      assert_patch(view, "/metrics_access?plan=business_pro&category=#{@category_slug}")

      assert has_element?(view, "#plan-business_pro[aria-current=true]")
      assert text(view, "##{mvrv}-api") == "2y · —"
      assert has_element?(view, "##{mvrv}-api [role=img][data-history=limited][data-delay=none]")
    end

    test "dates=exact shows resolved dates", %{conn: conn, mvrv_row: mvrv} do
      {:ok, view, _html} =
        live(conn, ~p"/metrics_access?plan=business_pro&category=#{@category_slug}")

      view |> element("#dates-exact") |> render_click()

      assert_patch(
        view,
        "/metrics_access?plan=business_pro&category=#{@category_slug}&dates=exact"
      )

      since = Date.add(Date.utc_today(), -730)
      # Short under the bar (month and year), the exact date on hover.
      assert text(view, "##{mvrv}-api") ==
               "since #{Calendar.strftime(since, "%b '%y")} · —"

      assert has_element?(
               view,
               "##{mvrv}-api[title='Since #{Date.to_iso8601(since)} · No delay']"
             )

      view |> element("#dates-relative") |> render_click()
      assert_patch(view, "/metrics_access?plan=business_pro&category=#{@category_slug}")
      assert text(view, "##{mvrv}-api") == "2y · —"
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
      assert text(view, "#category-#{@category_slug}") == "#{@category_name} (1 metric)"
    end

    test "regex characters in search do not crash and show the empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      change(view, %{"q" => "(*["})

      assert has_element?(view, "#metric-empty")
      refute has_element?(view, "[id$=metric-rows] [data-kind=row]")

      {:ok, view, _html} = live(conn, ~p"/metrics_access?q=.*")
      assert has_element?(view, "#metric-empty")
    end

    test "a seeded Pro-on-API metric is locked on Free via the API, without mocks", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      # "Locked", with the plan that unlocks it on a second line and in full on hover.
      assert text(view, "##{ctx.aave_row}-api") == "Locked Sanbase Pro"
      assert has_element?(view, "##{ctx.aave_row}-api[title='Requires Sanbase Pro']")
      assert has_element?(view, "##{ctx.aave_row}-api[data-locked]")
      assert has_element?(view, "##{ctx.aave_row}-api [role=img][data-state=locked]")
      assert has_element?(view, "##{ctx.aave_row}-api [role=img] [data-lockmark]")
      refute has_element?(view, "##{ctx.aave_row}-api [data-history]")
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
      refute has_element?(view, "#empty-clear-filters")
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

      assert text(view, "##{ctx.mvrv_row}-api") == "Locked Business Max"
      assert has_element?(view, "##{ctx.mvrv_row}-api[data-locked]")

      refute text(view, "##{ctx.mvrv_row}-sanbase") =~ "Locked"
      refute has_element?(view, "##{ctx.mvrv_row}-sanbase[data-locked]")
      refute has_element?(view, "##{ctx.mvrv_row}[data-locked]")

      # Locked in both channels mutes the whole row (shown with locked=show).
      :meck.expect(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, _product, _plan_name -> false
        query, product, plan_name -> :meck.passthrough([query, product, plan_name])
      end)

      PlanMetricAccess.expire_cache!()

      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}&locked=show")

      assert has_element?(view, "##{ctx.mvrv_row}[data-locked]")
      # No listed plan unlocks it: plainly locked, no plan named, no "custom plan".
      assert text(view, "##{ctx.mvrv_row}-sanbase") == "Locked"
      assert has_element?(view, "##{ctx.mvrv_row}-sanbase[title=Locked]")
      assert has_element?(view, "##{ctx.mvrv_row}-sanbase [role=img][data-state=locked]")
      assert has_element?(view, "##{ctx.mvrv_row}-sanbase [data-lockmark]")
    end

    test "the Included cards say matching metrics while a search or category narrows them", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?locked=show&category=#{@category_slug}")

      assert text(view, "#summary-api") =~ ~r/of 3 matching metrics/

      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?locked=show&q=price_usd")
      assert text(view, "#summary-api") =~ "matching metrics"

      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access")
      refute text(view, "#summary-api") =~ "matching"
    end

    test "Business plans say which Sanbase plan they include", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_pro")
      assert text(view, "#summary-sanbase-includes") == "Includes Sanbase Pro"
      assert has_element?(view, "#plan-business_pro[title='Includes Sanbase Pro']")

      {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_max")
      assert text(view, "#summary-sanbase-includes") == "Includes Sanbase Max"

      {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=sanbase_max")
      refute has_element?(view, "#summary-sanbase-includes")
    end
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

    test "counts metrics no listed plan unlocks as locked, with no plan named", %{
      conn: conn
    } do
      mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, _product, _plan_name -> false
        query, product, plan_name -> :meck.passthrough([query, product, plan_name])
      end)

      rows = PlanMetricAccess.rows()
      assert locked_count(rows, "business_max", :api, nil) >= 1

      {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_max")

      refute has_element?(view, "#summary-api-locked-custom")
      refute text(view, "#summary-api") =~ "custom"
      refute text(view, "#summary-api") =~ "Everything included"
      refute text(view, "#summary-api") =~ "need"

      included = Enum.count(rows, &(not match?({:locked, _}, &1.access[{"business_max", :api}])))
      # The number and "of N" are separate flex items, so textContent has no space.
      assert text(view, "#summary-api") =~ ~r/Included via API\s*#{included}\s*of #{length(rows)}/
    end
  end

  describe "show locked" do
    setup do
      # mvrv_usd locked in both channels on every plan; aave_v2_action_deposits stays
      # locked on Free via the API only.
      mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, _product, _plan_name -> false
        query, product, plan_name -> :meck.passthrough([query, product, plan_name])
      end)

      :ok
    end

    test "is off by default: rows locked in both channels are hidden", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      assert has_element?(view, "#show-locked[aria-checked=false]")
      refute has_element?(view, "##{ctx.mvrv_row}")
      # Locked in one channel only: stays.
      assert has_element?(view, "##{ctx.aave_row}")
      assert has_element?(view, "##{ctx.price_row}")
      # The count compares against the rows the locked setting leaves, and the
      # hiding itself is no filter: no chip for it.
      assert text(view, "#metric-count") ==
               "2 of #{visible_total("free")} metrics match your filters"

      refute has_element?(view, "#chip-locked")

      # Hiding locked rows alone does not make a count line.
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access")
      refute has_element?(view, "#metric-count")
    end

    test "locked=show reveals them, and the switch round-trips in the URL", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      view |> element("#show-locked") |> render_click()
      assert_patch(view, "/metrics_access?category=#{@category_slug}&locked=show")

      assert has_element?(view, "#show-locked[aria-checked=true]")
      assert has_element?(view, "##{ctx.mvrv_row}[data-locked]")

      view |> element("#show-locked") |> render_click()
      assert_patch(view, "/metrics_access?category=#{@category_slug}")
      refute has_element?(view, "##{ctx.mvrv_row}")
    end

    test "compare view always shows every row and has no switch", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?view=compare&category=#{@category_slug}")

      refute has_element?(view, "#show-locked")
      assert has_element?(view, "#compare-#{ctx.mvrv_row}")
    end
  end

  describe "access filter" do
    test "in plan view a row matches when either channel matches", ctx do
      %{price_row: price, mvrv_row: mvrv, aave_row: aave} = ctx

      # Free: price full in both; mvrv 2y + 30d (Sanbase), 1y + 30d (API);
      # aave 2y + 30d (Sanbase), locked (API).
      # Business Pro: price full in both; mvrv and aave full in Sanbase, 2y via API.
      cases = [
        {"free", "full", [price]},
        {"free", "no_delay", [price]},
        {"free", "delayed", [mvrv, aave]},
        {"free", "all_history", [price]},
        {"free", "limited_history", [mvrv, aave]},
        {"business_pro", "full", [price, mvrv, aave]},
        {"business_pro", "no_delay", [price, mvrv, aave]},
        {"business_pro", "limited_history", [mvrv, aave]},
        {"business_pro", "delayed", []}
      ]

      for {plan, access, expected} <- cases do
        {:ok, view, _html} =
          live(
            ctx.conn,
            ~p"/metrics_access?plan=#{plan}&category=#{@category_slug}&access=#{access}"
          )

        assert Enum.sort(row_ids(view)) == Enum.sort(expected),
               "#{plan} #{access}: #{inspect(row_ids(view))}"

        assert has_element?(view, "#access-select option[value=#{access}][selected]")
      end
    end

    test "the plan-view chip says either channel", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}&access=delayed")

      assert text(view, "#chip-access") == "Access: Delayed (Sanbase or API)"
    end

    test "locked cells never match a non-default option", ctx do
      # mvrv locked in both channels, shown with locked=show.
      mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, _product, _plan_name -> false
        query, product, plan_name -> :meck.passthrough([query, product, plan_name])
      end)

      for access <- ~w(full no_delay delayed all_history limited_history) do
        {:ok, view, _html} =
          live(
            ctx.conn,
            ~p"/metrics_access?category=#{@category_slug}&locked=show&access=#{access}"
          )

        refute has_element?(view, "##{ctx.mvrv_row}")
      end
    end

    test "changing it patches the URL; All metrics is the default and omitted", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      change(view, %{"access" => "delayed"})
      assert_patch(view, "/metrics_access?category=#{@category_slug}&access=delayed")
      assert Enum.sort(row_ids(view)) == Enum.sort([ctx.mvrv_row, ctx.aave_row])

      assert text(view, "#metric-count") ==
               "2 of #{visible_total("free")} metrics match your filters"

      change(view, %{"access" => "all"})
      assert_patch(view, "/metrics_access?category=#{@category_slug}")
    end
  end

  describe "sorting by column header" do
    test "an access column sorts best first, then worst first; ties keep taxonomy order", ctx do
      %{price_row: price, mvrv_row: mvrv, aave_row: aave} = ctx
      base = "/metrics_access?category=#{@category_slug}"

      {:ok, view, _html} = live(ctx.conn, base)
      assert href(view, "#sort-api") == base <> "&sort=api"
      refute has_element?(view, "#th-api[aria-sort]")

      # Free via the API: price best, mvrv 1y + delay, aave locked.
      view |> element("#sort-api") |> render_click()
      assert_patch(view, base <> "&sort=api")
      assert row_ids(view) == [price, mvrv, aave]
      assert has_element?(view, "#th-api[aria-sort=ascending]")
      assert href(view, "#sort-api") == base <> "&sort=api&dir=desc"

      view |> element("#sort-api") |> render_click()
      assert_patch(view, base <> "&sort=api&dir=desc")
      assert row_ids(view) == [aave, mvrv, price]
      assert has_element?(view, "#th-api[aria-sort=descending]")

      # A third click goes back to the default (taxonomy) order.
      assert href(view, "#sort-api") == base
      view |> element("#sort-api") |> render_click()
      assert_patch(view, base)
      refute has_element?(view, "[aria-sort]")
      assert href(view, "#sort-api") == base <> "&sort=api"
    end

    test "ties keep the taxonomy order in both directions", ctx do
      %{price_row: price} = ctx

      # In Sanbase on Free mvrv and aave tie (2y + 30d delay).
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")
      tied = row_ids(view) -- [price]

      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}&sort=sanbase")

      assert row_ids(view) == [price | tied]

      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}&sort=sanbase&dir=desc")

      assert row_ids(view) == List.insert_at(tied, -1, price)
    end

    test "the metric column sorts by technical name, A to Z then Z to A", ctx do
      %{price_row: price, mvrv_row: mvrv, aave_row: aave} = ctx
      base = "/metrics_access?category=#{@category_slug}"

      {:ok, view, _html} = live(ctx.conn, base)
      view |> element("#sort-metric") |> render_click()
      assert_patch(view, base <> "&sort=metric")
      assert row_ids(view) == [aave, mvrv, price]
      assert has_element?(view, "#th-metric[aria-sort=ascending]")

      view |> element("#sort-metric") |> render_click()
      assert_patch(view, base <> "&sort=metric&dir=desc")
      assert row_ids(view) == [price, mvrv, aave]
    end

    test "in compare view a plan header sorts by that plan's column", ctx do
      %{price_row: price, mvrv_row: mvrv, aave_row: aave} = ctx
      base = "/metrics_access?view=compare&category=#{@category_slug}"

      {:ok, view, _html} = live(ctx.conn, base)
      view |> element("#compare-plan-link-free") |> render_click()
      assert_patch(view, base <> "&sort=free")
      # Free via the API.
      assert row_ids(view) == [price, mvrv, aave]
      assert has_element?(view, "#compare-plan-free[aria-sort=ascending]")

      view |> element("#compare-plan-link-free") |> render_click()
      assert_patch(view, base <> "&sort=free&dir=desc")
      assert row_ids(view) == [aave, mvrv, price]

      view |> element("#compare-plan-link-business_max") |> render_click()

      # Sorting only: the compare view has no selected plan.
      assert_patch(view, base <> "&sort=business_max")
      assert has_element?(view, "#compare-plan-business_max[aria-sort=ascending]")
      refute has_element?(view, "#compare-plan-free[aria-sort]")
      refute has_element?(view, "[data-selected]")
    end

    test "plan view shows both channels and leaves channel out of its URLs", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?channel=sanbase&category=#{@category_slug}")

      assert has_element?(view, "#channel-switch[data-mode=both]")
      refute has_element?(view, "#channel-switch a")
      assert href(view, "#sort-api") == "/metrics_access?category=#{@category_slug}&sort=api"

      assert href(view, "#view-compare") ==
               "/metrics_access?view=compare&category=#{@category_slug}"
    end

    test "bogus sort and dir fall back to the default", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}&sort=nope&dir=sideways")

      {:ok, default, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      assert row_ids(view) == row_ids(default)
      refute has_element?(view, "[aria-sort]")
      assert href(view, "#sort-api") == "/metrics_access?category=#{@category_slug}&sort=api"
    end
  end

  describe "compare view" do
    test "renders one column per plan for the API by default", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?view=compare&category=#{@category_slug}")

      assert has_element?(view, "#view-compare[aria-current=true]")
      assert has_element?(view, "#compare-table")
      refute has_element?(view, "#plan-table")
      refute has_element?(view, "#plan-summary")
      # No selected plan in the compare view: no picker, access filter or show locked.
      refute has_element?(view, "#plan-picker [aria-current=true]:not(#view-compare)")
      refute has_element?(view, "#access-select")
      refute has_element?(view, "#show-locked")
      refute has_element?(view, "[data-selected]")
      assert has_element?(view, "#channel-api[aria-current=true]")
      # The channel is a real toggle here, in the sticky bar.
      assert has_element?(view, "#plan-bar #channel-switch[data-mode=toggle]")
      assert text(view, "#channel-label") == "Showing access via"
      assert has_element?(view, "#channel-switch a#channel-api[aria-current=true]")
      refute has_element?(view, "#channel-sanbase[aria-current]")
      assert has_element?(view, "#bar-key")
      assert has_element?(view, "#access-note")

      plan_keys =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#compare-table thead th[data-plan]")
        |> LazyHTML.attribute("data-plan")

      assert plan_keys == ["free", "sanbase_pro", "sanbase_max", "business_pro", "business_max"]

      # Free via the API.
      assert text(view, "#compare-#{ctx.mvrv_row}-free") == "1y · 30d"

      assert has_element?(
               view,
               "#compare-#{ctx.mvrv_row}-free [role=img][aria-label='Last 1 year · 30-day delay']"
             )

      assert has_element?(
               view,
               "#compare-#{ctx.mvrv_row}-free[title='Last 1 year · 30-day delay']"
             )

      assert text(view, "#compare-#{ctx.price_row}-business_max") == "Full"
      assert text(view, "#compare-#{ctx.mvrv_row}-business_pro") == "2y · —"
    end

    test "a locked cell says Locked, with the full text on hover", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?view=compare&category=#{@category_slug}")

      assert text(view, "#compare-#{ctx.aave_row}-free") == "Locked"
      assert has_element?(view, "#compare-#{ctx.aave_row}-free[title='Requires Sanbase Pro']")
      assert has_element?(view, "#compare-#{ctx.aave_row}-free [role=img][data-state=locked]")
    end

    test "the channel switch patches the URL and switches the cells", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?view=compare&category=#{@category_slug}")

      view |> element("#channel-sanbase") |> render_click()

      assert_patch(
        view,
        "/metrics_access?view=compare&channel=sanbase&category=#{@category_slug}"
      )

      assert has_element?(view, "#channel-sanbase[aria-current=true]")
      refute has_element?(view, "#channel-api[aria-current]")
      assert text(view, "#compare-count-free") =~ ~r/^in Sanbase · \d+ included$/
      assert text(view, "#compare-#{ctx.mvrv_row}-free") == "2y · 30d"
      assert text(view, "#compare-#{ctx.aave_row}-free") == "2y · 30d"

      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?view=compare&channel=sanbase")
      view |> element("#channel-api") |> render_click()
      assert_patch(view, "/metrics_access?view=compare")
    end

    test "each plan header counts the rows it includes in the channel", ctx do
      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?view=compare&category=#{@category_slug}")

      rows = Enum.filter(PlanMetricAccess.rows(), &(&1.category_slug == @category_slug))

      for %{key: plan} <- PlanMetricAccess.plans() do
        included = Enum.count(rows, &(not match?({:locked, _}, &1.access[{plan, :api}])))
        assert text(view, "#compare-count-#{plan}") == "via API · #{included} included"
      end

      assert text(view, "#compare-count-free") == "via API · 2 included"
    end

    test "the view switch keeps search and category, and drops plan-only params", ctx do
      {:ok, view, _html} =
        live(
          ctx.conn,
          ~p"/metrics_access?plan=business_pro&category=#{@category_slug}&q=usd&locked=show&access=delayed"
        )

      view |> element("#view-compare") |> render_click()
      assert_patch(view, "/metrics_access?view=compare&category=#{@category_slug}&q=usd")
      assert has_element?(view, "#compare-table")

      view |> element("#plan-free") |> render_click()
      assert_patch(view, "/metrics_access?category=#{@category_slug}&q=usd")
      assert has_element?(view, "#plan-table")
    end

    test "plan, access and locked params are ignored in compare view", ctx do
      {:ok, view, _html} =
        live(
          ctx.conn,
          ~p"/metrics_access?plan=business_pro&view=compare&category=#{@category_slug}&access=delayed&locked=show"
        )

      # Every row, no access chip, and the links leave those params out.
      assert length(row_ids(view)) == 3
      refute has_element?(view, "#chip-access")

      assert href(view, "#sort-metric") ==
               "/metrics_access?view=compare&category=#{@category_slug}&sort=metric"
    end

    test "the channel word is highlighted in the caption and every plan header", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?view=compare")

      assert has_element?(view, "#table-caption [data-channel=api]", "API")
      assert text(view, "#table-caption") == "Every plan, via the API"

      for %{key: plan} <- PlanMetricAccess.plans() do
        assert has_element?(view, "#compare-count-#{plan} [data-channel=api]", "API")
      end

      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?view=compare&channel=sanbase")
      assert has_element?(view, "#table-caption [data-channel=sanbase]", "Sanbase")
      assert text(view, "#table-caption") == "Every plan, via the Sanbase web app"
      assert has_element?(view, "#compare-count-free [data-channel=sanbase]", "Sanbase")

      # The plan view has no channel word to highlight.
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access")
      refute has_element?(view, "#table-caption [data-channel]")
    end

    test "the plan bar and the table header stick while the rows scroll", %{conn: conn} do
      for path <- ["/metrics_access", "/metrics_access?view=compare"] do
        {:ok, view, _html} = live(conn, path)

        # The bar measures its height for the header's offset.
        assert has_element?(view, "#plan-bar.sticky[phx-hook=PlanBarHeight]")
        # From md only: below it the table scrolls sideways in its own box, and a
        # sticky header there would be offset inside that box.
        assert has_element?(view, "table thead.md\\:sticky")
        refute has_element?(view, "table thead.sticky")
        # The caption with the bar legend is part of the sticky header.
        assert has_element?(view, "table thead #table-caption")
        assert has_element?(view, "table thead #bar-key")
      end
    end

    test "the metric column stays in place while the plan columns scroll", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")

      assert has_element?(view, "#compare-table thead th[data-sticky]")
      assert has_element?(view, "#compare-metric-rows tr td[data-sticky]")
      refute has_element?(view, "#plan-metric-rows")
    end

    test "pagination works", %{conn: conn} do
      total = length(PlanMetricAccess.rows())
      assert total > @page_size

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")

      assert length(row_ids(view)) == @page_size
      assert has_element?(view, "#load-more[phx-hook=LoadMoreOnVisible] #show-more")

      view |> element("#show-more") |> render_click()

      ids = row_ids(view)
      assert length(ids) == min(2 * @page_size, total)
      assert Enum.uniq(ids) == ids
    end
  end

  describe "category column" do
    test "the breadcrumb sits under the metric name; there is no Category column", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")

      headers =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#plan-table thead tr:last-child th")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))

      assert headers == ["Metric", "In Sanbase", "Via API"]
      refute has_element?(view, "#plan-table col#col-category")

      # One breadcrumb per row, in the metric cell, at every width.
      assert has_element?(view, "##{ctx.mvrv_row} > td:first-child ##{ctx.mvrv_row}-category")
      refute has_element?(view, "##{ctx.mvrv_row}-category-inline")
      refute has_element?(view, "##{ctx.mvrv_row} [class*='lg:hidden'] ##{ctx.mvrv_row}-category")

      assert text(view, "##{ctx.mvrv_row}-category") == "#{@category_name} Valuation"
      assert text(view, "##{ctx.price_row}-category") == "#{@category_name} Pricing"

      assert has_element?(
               view,
               "##{ctx.mvrv_row}-category[aria-label='Category: #{@category_name}, group: Valuation']"
             )

      hue = attribute(view, "##{ctx.mvrv_row}-category", "data-hue")
      assert hue not in [nil, "other"]
      assert attribute(view, "##{ctx.price_row}-category", "data-hue") == hue
      assert attribute(view, "##{ctx.aave_row}-category", "data-hue") == hue

      # It wraps rather than overflow, in a cell that may shrink.
      assert has_element?(view, "##{ctx.mvrv_row}-category.flex-wrap")
      assert has_element?(view, "##{ctx.mvrv_row} > td.min-w-0:first-child")
    end

    test "from md both tables fit without sideways scrolling", %{conn: conn} do
      for path <- ["/metrics_access", "/metrics_access?view=compare"] do
        {:ok, view, _html} = live(conn, path)

        # The table scrolls sideways (and the card clips) below md only.
        assert has_element?(view, "div.overflow-x-auto.md\\:overflow-visible > table")
        assert has_element?(view, ".overflow-clip.md\\:overflow-visible table")
        assert has_element?(view, "table.w-full.md\\:table-fixed")
        # No minimum width from md (one below md lets the compare table scroll).
        refute has_element?(view, "table[class*=' md:min-w'], table[class^='md:min-w']")
      end

      # Widths come from the colgroups (the first row is the full-width caption).
      {:ok, view, _html} = live(conn, ~p"/metrics_access")
      assert has_element?(view, "#plan-table colgroup col.md\\:w-\\[136px\\]")
      refute has_element?(view, "#plan-table colgroup col#col-category")

      # Compare: fixed-width plan columns, the metric column takes the rest.
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")

      widths =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#compare-table colgroup col.md\\:w-\\[104px\\]")
        |> Enum.count()

      assert widths == 5
    end

    test "an uncategorized row shows one muted Other segment", %{conn: conn} do
      row = Enum.find(PlanMetricAccess.rows(), &(&1.category == "Other"))
      assert row, "the seeded data must hold an uncategorized row"

      {:ok, view, _html} = live(conn, ~p"/metrics_access?locked=show&q=#{hd(row.metrics)}")

      assert text(view, "##{dom_id(row)}-category") == "Other"
      assert has_element?(view, "##{dom_id(row)}-category[data-hue=other]")
      assert has_element?(view, "##{dom_id(row)}-category[aria-label='Category: Other']")
    end
  end

  describe "active filters" do
    test "no chips and no count line when nothing narrows the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")

      refute has_element?(view, "#active-filters")
      refute has_element?(view, "#metric-count")
      refute has_element?(view, "#metric-search[data-active]")
      refute has_element?(view, "#search-clear")
    end

    test "the count line compares a search with the unfiltered total", %{conn: conn} do
      rows = PlanMetricAccess.rows()
      total = delimit(length(rows))

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&q=price_usd")
      matching = Enum.count(rows, &String.contains?(&1.search_text, "price_usd"))
      assert matching < @page_size

      assert text(view, "#metric-count") == "#{matching} of #{total} metrics match your filters"

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&q=_")
      matching = Enum.count(rows, &String.contains?(&1.search_text, "_"))
      assert matching > @page_size

      # Paging does not show in the count line.
      assert text(view, "#metric-count") ==
               "#{delimit(matching)} of #{total} metrics match your filters"
    end

    test "one removable chip per active filter, and Clear all", ctx do
      path =
        "/metrics_access?plan=business_pro&category=#{@category_slug}" <>
          "&q=usd&dates=exact&locked=show&access=all_history&sort=metric&dir=desc"

      {:ok, view, _html} = live(ctx.conn, path)

      assert has_element?(view, "#active-filters")
      assert text(view, "#chip-search") == ~s(Search: "usd")
      assert text(view, "#chip-category") == "Category: #{@category_name}"
      assert text(view, "#chip-access") == "Access: All history (Sanbase or API)"
      refute has_element?(view, "#chip-locked")

      assert href(view, "#chip-search") == String.replace(path, "&q=usd", "")

      assert href(view, "#chip-category") ==
               String.replace(path, "&category=#{@category_slug}", "")

      assert href(view, "#chip-access") == String.replace(path, "&access=all_history", "")

      assert href(view, "#clear-filters") ==
               "/metrics_access?plan=business_pro&dates=exact&locked=show"

      assert has_element?(view, "#metric-search[data-active]")
      assert href(view, "#search-clear") == String.replace(path, "&q=usd", "")

      view |> element("#chip-search") |> render_click()
      assert_patch(view, String.replace(path, "&q=usd", ""))
      refute has_element?(view, "#chip-search")
      assert has_element?(view, "#chip-category")
    end

    test "hidden locked rows never make a chip; the count follows the switch", ctx do
      mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fn
        {:metric, "mvrv_usd"}, _product, _plan_name -> false
        query, product, plan_name -> :meck.passthrough([query, product, plan_name])
      end)

      total = length(PlanMetricAccess.rows())
      hidden = visible_total("free")
      assert hidden < total

      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")
      refute has_element?(view, "#chip-locked")
      refute text(view, "#metrics-access") =~ "Locked hidden"
      assert text(view, "#metric-count") == "2 of #{hidden} metrics match your filters"

      {:ok, view, _html} =
        live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}&locked=show")

      refute has_element?(view, "#chip-locked")
      assert text(view, "#metric-count") == "3 of #{total} metrics match your filters"

      # Clear all keeps the Show locked setting.
      assert href(view, "#clear-filters") == "/metrics_access?locked=show"
    end

    test "the empty result keeps a Clear filters action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&q=zzzz_no_such_metric")

      assert has_element?(view, "#metric-empty")
      assert href(view, "#empty-clear-filters") == "/metrics_access?view=compare"
    end
  end

  describe "variants" do
    @active_addresses ~w(active_addresses_1h active_addresses_24h active_addresses_7d
                         active_addresses_30d active_addresses_60d active_addresses_90d)

    setup do
      row = row_for(PlanMetricAccess.rows(), "active_addresses_24h")
      assert Enum.sort(row.metrics) == Enum.sort(@active_addresses)
      %{aa_row: row}
    end

    test "collapsed by default: one row with +5 variants", %{conn: conn, aa_row: row} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?locked=show&q=active_addresses_")

      assert has_element?(view, "#variants-collapsed[aria-pressed=true]")
      assert text(view, "##{dom_id(row)}") =~ "+5 variants"
      refute Enum.any?(row_ids(view), &String.contains?(&1, "--"))
    end

    test "variants=expanded lists each variant as its own row, in interval order", %{
      conn: conn,
      aa_row: row
    } do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?locked=show&q=active_addresses_")

      view |> element("#variants-expanded") |> render_click()
      assert_patch(view, "/metrics_access?q=active_addresses_&locked=show&variants=expanded")
      assert has_element?(view, "#variants-expanded[aria-pressed=true]")

      prefix = dom_id(row) <> "--"
      ids = view |> row_ids() |> Enum.filter(&String.starts_with?(&1, prefix))

      assert ids == Enum.map(@active_addresses, &(prefix <> &1))
      assert Enum.uniq(row_ids(view)) == row_ids(view)

      first = prefix <> "active_addresses_1h"
      assert text(view, "##{first}") =~ "active_addresses_1h"
      assert text(view, "##{first}") =~ row.variant_names["active_addresses_1h"]
      refute text(view, "##{first}") =~ "variants"
    end

    test "the tooltip explains variants and is wired to the whole control", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      tooltip = "#variants-help-tooltip"
      assert has_element?(view, "#{tooltip}[role=tooltip]")

      # It shows while the control (both options and the icon) is hovered or focused.
      for id <- ~w(variants-collapsed variants-expanded variants-help) do
        assert has_element?(view, "##{id}[aria-describedby=variants-help-tooltip]")
      end

      assert text(view, "#{tooltip} [data-part=title]") == "What are variants?"

      assert text(view, "#{tooltip} [data-part=summary]") ==
               "The same measurement computed over different time windows, listed as one row."

      assert text(view, "#{tooltip} [data-part=base]") == "active_addresses"

      for {suffix, window} <- [
            {"_1h", "the last hour"},
            {"_24h", "the last 24 hours"},
            {"_7d", "the last 7 days"}
          ] do
        assert text(view, "#{tooltip} [data-example='#{suffix}']") ==
                 "#{suffix} unique addresses active in #{window}"
      end

      assert text(view, "#{tooltip} [data-part=footer]") ==
               "Expand variants to list each one as its own row."
    end

    test "counts say metrics when collapsed and metric variants when expanded", %{conn: conn} do
      rows = PlanMetricAccess.rows()
      variants = rows |> Enum.flat_map(& &1.metrics) |> length()

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&q=_")

      assert text(view, "#metric-count") =~
               ~r/ of #{delimit(length(rows))} metrics match your filters$/

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&q=_&variants=expanded")

      assert text(view, "#metric-count") =~
               ~r/ of #{delimit(variants)} metric variants match your filters$/

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&variants=expanded")
      assert text(view, "#category-all") =~ "metric variants"

      {:ok, view, _html} = live(conn, ~p"/metrics_access?variants=expanded")
      assert text(view, "#summary-api") =~ "metric variants"
    end

    test "the segmented buttons survive what a browser sends", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?q=active_addresses_")

      # LiveView's client puts a button's `value` property into the payload as
      # "value"; each button carries its option as its value, and the option
      # travels under its own key, so the two cannot collide.
      assert has_element?(view, "#variants-expanded[value=expanded][phx-value-option=expanded]")
      assert has_element?(view, "#variants-collapsed[value=collapsed]")
      assert has_element?(view, "#dates-exact[value=exact][phx-value-option=exact]")
      assert has_element?(view, "#dates-relative[value=relative]")

      # The payload a browser sends for a value-less button: "value" => "".
      render_click(view, "variants", %{"option" => "expanded", "value" => ""})
      assert_patch(view, "/metrics_access?q=active_addresses_&variants=expanded")

      render_click(view, "dates", %{"option" => "exact", "value" => ""})
      assert_patch(view, "/metrics_access?q=active_addresses_&dates=exact&variants=expanded")
    end

    test "bogus values fall back to collapsed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?variants=nope")
      assert has_element?(view, "#variants-collapsed[aria-pressed=true]")
    end
  end

  describe "review fixes" do
    test "load more stops when the cached rows shrank under the page", %{conn: conn} do
      rows = PlanMetricAccess.rows()
      assert length(rows) > @page_size
      :persistent_term.put({__MODULE__, :rows}, rows)
      on_exit(fn -> :persistent_term.erase({__MODULE__, :rows}) end)
      mock(PlanMetricAccess, :rows, fn -> :persistent_term.get({__MODULE__, :rows}) end)

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")
      assert has_element?(view, "#load-more")

      # A refresh drops rows: nothing is left after what is on screen.
      :persistent_term.put({__MODULE__, :rows}, Enum.take(rows, @page_size))
      view |> element("#show-more") |> render_click()

      refute has_element?(view, "#load-more")
      assert length(row_ids(view)) == @page_size
    end

    test "a sort from the other view does not leak in", ctx do
      # A plan column sort means nothing in the plan view...
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?sort=free&dir=desc")
      refute has_element?(view, "[aria-sort]")
      refute has_element?(view, "[aria-sort=descending]")

      # ...and a channel column sort nothing in the compare view.
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?view=compare&sort=api")
      refute has_element?(view, "[aria-sort]")

      # Switching views drops the sort that does not apply there.
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?sort=api")
      assert href(view, "#view-compare") == "/metrics_access?view=compare"

      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?view=compare&sort=free")
      assert href(view, "#plan-business_pro") == "/metrics_access?plan=business_pro"

      # A metric sort applies in both.
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?sort=metric")
      assert href(view, "#view-compare") == "/metrics_access?view=compare&sort=metric"
    end

    test "Clear all keeps the compare channel and the variants mode", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, ~p"/metrics_access?view=compare&channel=sanbase&q=usd&variants=expanded")

      assert href(view, "#clear-filters") ==
               "/metrics_access?view=compare&channel=sanbase&variants=expanded"
    end

    test "the legend popover opens in place, in the sticky header, without scrolling", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      # Anchored in the sticky caption row, so it opens where the button is even
      # when the header is stuck.
      assert has_element?(view, "thead th.relative #bar-help[role=dialog]")
      assert has_element?(view, "#bar-help button#bar-help-close[aria-label='Close']")

      # The button and the dialog share the click-away / Esc wrapper.
      wrapper = "[phx-click-away]"
      assert has_element?(view, "#{wrapper} #bar-help-button")
      assert has_element?(view, "#{wrapper} #bar-help")

      # Focus moves with preventScroll (a window listener), never a scrolling focus.
      assert has_element?(view, "#bar-help-button[phx-click*='metrics:focus']")
      refute has_element?(view, "[phx-click*='\"focus\"']")
    end

    test "a cell's hidden separator stays inside the cell", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?category=nope&q=mvrv_usd")
      # The sr-only dot is absolutely positioned: its code grid must contain it,
      # or it escapes the table's scroller and widens the page on phones.
      assert has_element?(view, "[data-part=code].relative .sr-only")
    end

    test "the count line's live region is always mounted", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")
      assert has_element?(view, "#metric-count-region[aria-live=polite]")
      refute has_element?(view, "#metric-count")

      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&q=usd")
      assert has_element?(view, "#metric-count-region[aria-live=polite] #metric-count")
    end

    test "the plan view's channel indicator is not a disabled control", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      refute has_element?(view, "#channel-switch [aria-disabled]")
      assert has_element?(view, "#channel-switch .sr-only", "This view shows both channels")
    end

    test "Escape closes the popover and the explainer only when they are open", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      # No window-wide Escape commands that would act while closed: Escape is
      # handled in app.js, which checks the popover / tooltip is open first.
      refute has_element?(view, "[phx-window-keydown]")

      assert has_element?(
               view,
               "#bar-help[data-dismiss=escape][data-return-focus=bar-help-button]"
             )

      assert has_element?(view, "#variants-help-tooltip[data-dismiss=escape]")
      # The explainer can be hovered: the pointer can move onto it.
      refute has_element?(view, "#variants-help-tooltip.pointer-events-none")
      refute has_element?(view, "#variants-help[phx-keydown]")
    end

    test "malformed dates and variants events are ignored", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")
      render_click(view, "dates", %{"bogus" => "x"})
      render_click(view, "variants", %{})
      assert has_element?(view, "#plan-table")
    end

    test "dir without a sort is ignored: the default order has no direction", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?dir=desc")
      refute has_element?(view, "[aria-sort]")
      refute has_element?(view, "[aria-sort=descending]")
      assert href(view, "#sort-metric") == "/metrics_access?sort=metric"
    end
  end

  describe "API call limits" do
    test "an API plan's card shows its limits, with the full numbers for readers", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?plan=business_pro")

      card = "#summary-api-calls"
      assert text(view, "#{card} [data-part=month]") == "600K / month"
      assert text(view, "#{card} [data-part=hour]") == "30K / hour"
      assert text(view, "#{card} [data-part=minute]") == "600 / min"

      assert has_element?(
               view,
               "#{card}[aria-label='API calls: 600,000 calls per month, 30,000 per hour, 600 per minute']"
             )

      assert has_element?(view, "#{card}[data-hue=purple]")
    end

    test "Free and Sanbase Pro say they are not meant for API access", %{conn: conn} do
      for plan <- ["free", "sanbase_pro"] do
        {:ok, view, _html} = live(conn, "/metrics_access?plan=#{plan}")

        assert text(view, "#summary-api-calls") =~ "Not meant for API access"
        refute has_element?(view, "#summary-api-calls [data-part=month]")
      end
    end

    test "the compare view's API headers carry each plan's limits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")

      for {plan, pill} <- [
            {"free", "Not for API"},
            {"sanbase_pro", "Not for API"},
            {"sanbase_max", "80K/mo · 100/min"},
            {"business_pro", "600K/mo · 600/min"},
            {"business_max", "1.2M/mo · 1.2K/min"}
          ] do
        assert text(view, "#compare-plan-#{plan} #compare-limits-#{plan}") == pill
      end

      assert has_element?(
               view,
               "#compare-limits-business_max[title='1,200,000 calls per month, 60,000 per hour, 1,200 per minute']"
             )

      # Not on the Sanbase channel.
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&channel=sanbase")
      refute has_element?(view, "[id^=compare-limits-]")
    end
  end

  describe "mobile (below md only)" do
    test "plan view rows stack: the metric on top, the two channels side by side", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/metrics_access?category=#{@category_slug}")
      row = "##{ctx.mvrv_row}"

      # Below md only the column-name row is hidden; the caption row (bar key and
      # "What do these mean?") stays.
      refute has_element?(view, "#plan-table thead.max-md\\:hidden")
      assert has_element?(view, "#plan-table.max-md\\:block thead tr.max-md\\:hidden #th-metric")
      refute has_element?(view, "#plan-table thead tr.max-md\\:hidden #bar-help-button")
      assert has_element?(view, "#plan-table thead tr.max-md\\:block #bar-help-button")
      assert has_element?(view, "#{row}.max-md\\:grid.max-md\\:grid-cols-2")
      assert has_element?(view, "#{row} > td.max-md\\:col-span-2 a", "mvrv_usd")
      assert has_element?(view, "#{row} > td.max-md\\:col-span-2 ##{ctx.mvrv_row}-category")

      # A label above each bar, drawn from the cell's data-label (CSS only, so
      # it adds no text and nothing at md and up).
      assert has_element?(view, "#{row}-sanbase[data-label='In Sanbase']")
      assert has_element?(view, "#{row}-api[data-label='Via API']")
      assert text(view, "#{row}-api") == "1y · 30d"
    end

    test "the plan options scroll sideways in one row; the plan view drops the channel line",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/metrics_access")

      assert has_element?(view, "#plan-picker.max-md\\:flex-nowrap.max-md\\:overflow-x-auto")
      assert has_element?(view, ".max-md\\:hidden #channel-switch[data-mode=both]")

      # The compare view keeps its channel toggle.
      {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare")
      refute has_element?(view, ".max-md\\:hidden #channel-switch")
    end
  end

  test "bogus params fall back to defaults", %{conn: conn} do
    {:ok, view, _html} =
      live(
        conn,
        ~p"/metrics_access?plan=bogus&category=nope&dates=foo&view=nope&channel=nope&locked=nope&access=nope&sort=nope"
      )

    assert has_element?(view, "#plan-free[aria-current=true]")
    assert has_element?(view, "#category-select #category-all[selected]")
    assert has_element?(view, "#dates-relative[aria-pressed=true]")
    assert has_element?(view, "#channel-switch[data-mode=both]")
    assert has_element?(view, "#show-locked[aria-checked=false]")
    assert has_element?(view, "#access-select option[value=all][selected]")
    assert has_element?(view, "#th-metric")
    refute has_element?(view, "[aria-sort=descending]")
    assert has_element?(view, "[id$=metric-rows] [data-kind=row]")

    {:ok, view, _html} = live(conn, ~p"/metrics_access?view=compare&channel=nope")
    assert has_element?(view, "#compare-table")
    assert has_element?(view, "#channel-api[aria-current=true]")
  end

  test "every param round-trips through the URL", %{conn: conn} do
    path =
      "/metrics_access?plan=business_pro&q=_&dates=exact&locked=show&access=delayed" <>
        "&sort=metric&dir=desc&variants=expanded"

    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, "#plan-business_pro[aria-current=true]")
    assert has_element?(view, "#dates-exact[aria-pressed=true]")
    assert has_element?(view, "#show-locked[aria-checked=true]")
    assert has_element?(view, "#access-select option[value=delayed][selected]")
    assert has_element?(view, "#plan-table th[aria-sort=descending] #sort-metric")
    assert has_element?(view, "#variants-expanded[aria-pressed=true]")

    # A plan click rebuilds the URL from the parsed state: nothing is lost.
    view |> element("#plan-business_max") |> render_click()
    assert_patch(view, String.replace(path, "business_pro", "business_max"))

    compare = "/metrics_access?view=compare&channel=sanbase&q=_&dates=exact&sort=free&dir=desc"
    {:ok, view, _html} = live(conn, compare)

    assert has_element?(view, "#channel-sanbase[aria-current=true]")
    assert has_element?(view, "#compare-plan-free[aria-sort=descending]")
    view |> element("#dates-relative") |> render_click()
    assert_patch(view, String.replace(compare, "&dates=exact", ""))
  end

  test "only the first page renders, Show more appends the next", %{conn: conn} do
    total = length(PlanMetricAccess.rows())
    assert total > @page_size, "the seeded test DB must hold more rows than one page"

    {:ok, view, _html} = live(conn, ~p"/metrics_access?locked=show")

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

  test "a view, channel, locked, access or sort change starts from one page", %{conn: conn} do
    plan = "/metrics_access?locked=show"

    steps = [
      {plan, fn view -> view |> element("#view-compare") |> render_click() end},
      {"/metrics_access?view=compare",
       fn view -> view |> element("#channel-sanbase") |> render_click() end},
      {plan, fn view -> view |> element("#show-locked") |> render_click() end},
      {plan, fn view -> change(view, %{"access" => "all_history"}) end},
      {plan, fn view -> view |> element("#sort-metric") |> render_click() end},
      {plan, fn view -> view |> element("#variants-expanded") |> render_click() end}
    ]

    for {path, step} <- steps do
      {:ok, view, _html} = live(conn, path)
      view |> element("#show-more") |> render_click()
      assert length(row_ids(view)) == 2 * @page_size

      step.(view)
      assert length(row_ids(view)) <= @page_size
    end
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

  defp attribute(view, selector, name) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute(name)
    |> List.first()
  end

  defp href(view, selector), do: attribute(view, selector, "href")

  defp delimit(n), do: SanbaseWeb.MetricsAccessComponents.delimit(n)

  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[id$=metric-rows] [data-kind=row]")
    |> LazyHTML.attribute("id")
    # Compare rows carry a view prefix; compare them by their plan-view ids.
    |> Enum.map(&String.replace_prefix(&1, "compare-", ""))
  end

  # Rows the plan view shows with locked rows hidden (no other filter).
  defp visible_total(plan) do
    Enum.count(PlanMetricAccess.rows(), fn row ->
      not (match?({:locked, _}, row.access[{plan, :sanbase}]) and
             match?({:locked, _}, row.access[{plan, :api}]))
    end)
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

  # A mock changes what the rows are made of: the cached rows are dropped so the
  # page computes them with the mock in place.
  defp mock(mod, fun, impl) do
    :meck.new(mod, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(mod) end)
    :meck.expect(mod, fun, impl)
    PlanMetricAccess.expire_cache!()
  end
end
