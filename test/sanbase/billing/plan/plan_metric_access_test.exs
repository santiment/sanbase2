defmodule Sanbase.Billing.Plan.PlanMetricAccessTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Billing.Plan.PlanMetricAccess
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.MetricGroup

  @metric "mvrv_usd"

  # rows/0 is cached in a :persistent_term that outlives each test.
  setup do
    PlanMetricAccess.expire_cache!()
    on_exit(&PlanMetricAccess.expire_cache!/0)
  end

  test "plans and channels are listed in display order" do
    assert Enum.map(PlanMetricAccess.plans(), & &1.key) ==
             ["free", "sanbase_pro", "sanbase_max", "business_pro", "business_max"]

    assert Enum.map(PlanMetricAccess.channels(), & &1.key) == [:sanbase, :api]

    assert %{
             label: "Business Pro",
             plan_name: "BUSINESS_PRO",
             subscription_product: "SANAPI",
             includes: "sanbase_pro"
           } = Enum.find(PlanMetricAccess.plans(), &(&1.key == "business_pro"))

    assert Map.new(PlanMetricAccess.plans(), &{&1.key, &1.includes}) == %{
             "free" => nil,
             "sanbase_pro" => nil,
             "sanbase_max" => nil,
             "business_pro" => "sanbase_pro",
             "business_max" => "sanbase_max"
           }
  end

  test "an unrestricted metric is all history with no delay on every plan and channel" do
    metric = Sanbase.Metric.free_metrics() |> Enum.sort() |> hd()

    for %{key: plan} <- PlanMetricAccess.plans(),
        %{key: channel} <- PlanMetricAccess.channels() do
      assert PlanMetricAccess.access({:metric, metric}, plan, channel) == {:window, nil, nil}
    end
  end

  test "headline windows match the checker modules" do
    assert PlanMetricAccess.headline("free", :sanbase) == {730, 30}
    assert PlanMetricAccess.headline("free", :api) == {365, 30}
    assert PlanMetricAccess.headline("sanbase_pro", :sanbase) == {nil, nil}
    assert PlanMetricAccess.headline("sanbase_pro", :api) == {365, 30}
    assert PlanMetricAccess.headline("sanbase_max", :api) == {730, nil}
    assert PlanMetricAccess.headline("business_pro", :sanbase) == {nil, nil}
    assert PlanMetricAccess.headline("business_pro", :api) == {730, nil}
    assert PlanMetricAccess.headline("business_max", :api) == {nil, nil}
  end

  test "a restricted metric gets the plan window" do
    m = {:metric, @metric}
    assert PlanMetricAccess.access(m, "business_pro", :api) == {:window, 730, nil}
    assert PlanMetricAccess.access(m, "free", :api) == {:window, 365, 30}
    assert PlanMetricAccess.access(m, "free", :sanbase) == {:window, 730, 30}
    assert PlanMetricAccess.access(m, "business_max", :api) == {:window, nil, nil}
  end

  test "a seeded metric with a Pro min plan on the API is locked on Free via the API" do
    # Seeded with min plan SANAPI "pro", SANBASE "free"; nothing is mocked.
    m = {:metric, "aave_v2_action_deposits"}

    assert PlanMetricAccess.access(m, "free", :api) == {:locked, "sanbase_pro"}
    assert PlanMetricAccess.access(m, "free", :sanbase) == {:window, 730, 30}
    assert PlanMetricAccess.access(m, "sanbase_pro", :api) == {:window, 365, 30}
    assert PlanMetricAccess.access(m, "business_pro", :api) == {:window, 730, nil}
  end

  test "every row agrees with Restrictions.get/4, the getAccessRestrictions answer" do
    # The page must never promise more or less than enforcement serves. Day counts
    # are compared with a one-day tolerance: Restrictions.get/4 shifts from now.
    now = DateTime.utc_now()

    days_ago = fn
      nil -> nil
      datetime -> DateTime.diff(now, datetime, :day)
    end

    close? = fn
      nil, nil -> true
      a, b when is_integer(a) and is_integer(b) -> abs(a - b) <= 1
      _, _ -> false
    end

    rows = PlanMetricAccess.compute_rows()
    assert length(rows) > 100

    mismatches =
      for row <- rows,
          metric <- row.metrics,
          plan <- PlanMetricAccess.plans(),
          %{key: channel, product: product} <- PlanMetricAccess.channels(),
          access = row.access[{plan.key, channel}],
          restriction =
            Sanbase.Billing.Plan.Restrictions.get(
              {:metric, metric},
              product,
              plan.subscription_product || product,
              plan.plan_name
            ),
          not agrees?(access, restriction, days_ago, close?) do
        {metric, plan.key, channel, access,
         Map.take(restriction, [:is_accessible, :is_restricted, :restricted_from, :restricted_to])}
      end

    assert mismatches == []
  end

  test "a max-only metric is locked below max, with the lowest unlocking plan" do
    # plan_has_access? reads the min plan through a local call, which meck cannot
    # intercept, so model a "max" min plan on both products directly.
    mock_plan_has_access(fn _query, product, plan_name ->
      Sanbase.Billing.Plan.StandardAccessChecker.max_plan?(product, plan_name)
    end)

    m = {:metric, @metric}

    assert PlanMetricAccess.access(m, "free", :sanbase) == {:locked, "sanbase_max"}
    assert PlanMetricAccess.access(m, "sanbase_pro", :sanbase) == {:locked, "sanbase_max"}
    assert PlanMetricAccess.access(m, "business_pro", :sanbase) == {:locked, "sanbase_max"}
    assert {:window, _, _} = PlanMetricAccess.access(m, "sanbase_max", :sanbase)
    assert PlanMetricAccess.access(m, "business_pro", :api) == {:locked, "business_max"}
    assert {:window, nil, nil} = PlanMetricAccess.access(m, "business_max", :api)
  end

  test "a free-access metric above the plan's min plan is locked, as enforcement does" do
    # Enforcement checks plan_has_access? before restricted?, so a free metric
    # with a higher min plan is denied, not served.
    metric = "daily_active_addresses"
    m = {:metric, metric}
    refute Sanbase.Billing.Plan.AccessChecker.restricted?(m)

    mock_plan_has_access(fn
      {:metric, ^metric}, _product, "FREE" -> false
      query, product, plan_name -> :meck.passthrough([query, product, plan_name])
    end)

    assert PlanMetricAccess.access(m, "free", :api) == {:locked, "sanbase_pro"}
    assert PlanMetricAccess.access(m, "free", :sanbase) == {:locked, "sanbase_pro"}
    assert PlanMetricAccess.access(m, "sanbase_pro", :api) == {:window, nil, nil}
  end

  test "a metric no listed plan unlocks is {:locked, nil}" do
    mock_plan_has_access(fn _, _, _ -> false end)

    assert PlanMetricAccess.access({:metric, @metric}, "free", :api) == {:locked, nil}
    assert PlanMetricAccess.access({:metric, @metric}, "business_max", :sanbase) == {:locked, nil}
  end

  describe "compute_rows/0" do
    # Served by an adapter module, not the registry, so these are code rows and the
    # mappings below are module/metric rows that exist in every environment.
    @price_module "Sanbase.Price.MetricAdapter"
    @registry_module "Sanbase.Clickhouse.MetricAdapter"
    @template "mvrv_usd_{{timebound}}"

    setup do
      {:ok, category} = MetricCategory.create(%{name: "PMA Test Market", display_order: 1})

      {:ok, pricing} =
        MetricGroup.create(%{name: "Pricing", category_id: category.id, display_order: 1})

      {:ok, internal} =
        MetricGroup.create(%{
          name: "Internal Metrics",
          category_id: category.id,
          display_order: 2
        })

      %{category: category, pricing: pricing, internal: internal}
    end

    test "a registry-mapped category whose template raises does not break the rows", ctx do
      registry = registry!(@template)

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: ctx.category.id,
          group_id: ctx.pricing.id,
          display_order: 1
        })

      mock(Sanbase.Metric.Registry, :resolve_registry, fn
        %{id: id} when id == registry.id -> raise "broken template"
        other -> :meck.passthrough([other])
      end)

      {rows, log} = ExUnit.CaptureLog.with_log(&PlanMetricAccess.compute_rows/0)

      assert length(rows) > 100
      assert log =~ "broken template"
    end

    test "registry template variants collapse into one row with a clean name" do
      registry = registry!(@template)
      variants = released_variants(registry)
      assert length(variants) > 1

      rows = PlanMetricAccess.compute_rows()
      assert [row] = Enum.filter(rows, &Enum.any?(&1.metrics, fn m -> m in variants end))

      assert row.id == "r-#{registry.id}"
      assert row.metrics == Enum.sort(variants)
      assert row.name == "MVRV for coins that moved"
      refute Enum.any?(rows, &String.contains?(&1.name, ["{{", "}}"]))
    end

    test "each name of a row carries its own display name, for the expanded variants" do
      rows = PlanMetricAccess.compute_rows()
      row = row_for(rows, "active_addresses_24h")
      assert length(row.metrics) > 1

      assert Map.keys(row.variant_names) |> Enum.sort() == Enum.sort(row.metrics)

      for metric <- row.metrics do
        expected =
          case Sanbase.Metric.human_readable_name(metric) do
            {:ok, name} when is_binary(name) and name != "" -> name
            _ -> metric
          end

        assert row.variant_names[metric] == expected
      end

      # A variant's display name is searchable too.
      assert row.search_text =~ String.downcase(row.variant_names["active_addresses_24h"])
    end

    test "blank display names fall back to the metric name" do
      registry = registry!(@template)

      update_registry!(registry, human_readable_name: "{{timebound:human_readable}}")

      mock(Sanbase.Metric, :human_readable_name, fn
        "price_usd" -> {:ok, nil}
        metric -> :meck.passthrough([metric])
      end)

      rows = PlanMetricAccess.compute_rows()

      template_row = Enum.find(rows, &(&1.id == "r-#{registry.id}"))
      assert template_row.name == hd(template_row.metrics)
      assert row_for(rows, "price_usd").name == "price_usd"
    end

    test "code-defined metrics appear as their own rows" do
      row = row_for(PlanMetricAccess.compute_rows(), "price_usd")

      assert row.id == "m-price_usd"
      assert row.metrics == ["price_usd"]
      assert row.name == "Price in USD"

      assert map_size(row.access) == 10

      assert row.access[{"free", :api}] ==
               PlanMetricAccess.access({:metric, "price_usd"}, "free", :api)
    end

    test "each row carries a downcased search text of its display and technical names" do
      rows = PlanMetricAccess.compute_rows()

      price = row_for(rows, "price_usd")
      assert price.search_text =~ "price in usd"
      assert price.search_text =~ "price_usd"

      template = row_for(rows, "mvrv_usd_30d")
      assert Enum.all?(template.metrics, &String.contains?(template.search_text, &1))
      assert Enum.all?(rows, &(&1.search_text == String.downcase(&1.search_text)))
    end

    test "a name two registry rows resolve to goes to the usable row, with one warning" do
      registry = registry!("mvrv_usd")
      # Warm the stored terms before Registry.all/0 is mocked (see update_registry!/2).
      _ = PlanMetricAccess.compute_rows()

      # Listed after the original, so a last-write-wins index would pick it and
      # drop the metric with it.
      duplicate = %{registry | id: registry.id + 1_000_000, is_deprecated: true}

      mock(Sanbase.Metric.Registry, :all, fn ->
        List.insert_at(:meck.passthrough([]), -1, duplicate)
      end)

      {rows, log} = ExUnit.CaptureLog.with_log(&PlanMetricAccess.compute_rows/0)

      assert %{id: id} = row_for(rows, "mvrv_usd")
      assert id == "r-#{registry.id}"
      assert log =~ "mvrv_usd"
      assert length(String.split(log, "registry rows share")) == 2
    end

    test "alpha/beta, deprecated and hidden metrics are excluded" do
      registry = registry!("mvrv_usd")

      update_registry!(registry, is_deprecated: true)

      mock(Sanbase.Metric, :metadata, fn
        "price_btc" = metric ->
          with {:ok, m} <- :meck.passthrough([metric]), do: {:ok, %{m | status: "beta"}}

        "volume_usd" = metric ->
          with {:ok, m} <- :meck.passthrough([metric]),
               do: {:ok, Map.put(m, :is_deprecated, true)}

        metric ->
          :meck.passthrough([metric])
      end)

      metrics = PlanMetricAccess.compute_rows() |> Enum.flat_map(& &1.metrics) |> MapSet.new()

      # A deprecated registry row is dropped as a whole, not demoted to a code row.
      refute Enum.any?(
               Sanbase.Metric.Registry.resolve_registry(registry),
               &(&1.metric in metrics)
             )

      refute "price_btc" in metrics
      refute "volume_usd" in metrics
      assert "price_usd" in metrics

      alpha =
        Enum.filter(Sanbase.Metric.available_metrics(), fn metric ->
          match?(
            {:ok, %{status: status}} when status in ["alpha", "beta"],
            Sanbase.Metric.metadata(metric)
          )
        end)

      assert alpha != []
      assert Enum.all?(alpha, &(&1 not in metrics))
      # available_metrics/0 without options keeps hidden metrics, so they need
      # their own filter.
      hidden = Sanbase.Metric.hidden_metrics()
      assert Enum.any?(Sanbase.Metric.available_metrics(), &(&1 in hidden))
      assert Enum.all?(hidden, &(&1 not in metrics))
    end

    test "metrics only in a hidden group are excluded", ctx do
      map_metric("price_btc", ctx.category, ctx.internal)
      map_metric("price_usd", ctx.category, ctx.internal)
      map_metric("price_usd", ctx.category, ctx.pricing)

      rows = PlanMetricAccess.compute_rows()

      refute row_for(rows, "price_btc")
      assert %{category: "PMA Test Market", group: "Pricing"} = row_for(rows, "price_usd")
    end

    test "a variant mapped only to hidden groups is dropped from its row", ctx do
      # A registry-id mapping applies to every variant, so a variant can only be
      # internal-only through name mappings: one sibling places the row in a public
      # group, another variant is mapped only to Internal Metrics.
      registry = registry!(@template)
      [internal, public | _] = registry |> released_variants() |> Enum.sort()

      map_metric(public, ctx.category, ctx.pricing, @registry_module)
      map_metric(internal, ctx.category, ctx.internal, @registry_module)

      rows = PlanMetricAccess.compute_rows()

      assert %{id: id, group: "Pricing", metrics: metrics} = row_for(rows, public)
      assert id == "r-#{registry.id}"
      refute internal in metrics
      refute row_for(rows, internal)
    end

    test "a registry row hidden in the DB is excluded before stored terms refresh" do
      registry = registry!("mvrv_usd")
      names = registry |> Sanbase.Metric.Registry.resolve_registry() |> Enum.map(& &1.metric)
      shown = fn -> PlanMetricAccess.compute_rows() |> Enum.flat_map(& &1.metrics) end
      assert Enum.any?(names, &(&1 in shown.()))

      update_registry!(registry, is_hidden: true)

      metrics = PlanMetricAccess.compute_rows() |> Enum.flat_map(& &1.metrics) |> MapSet.new()
      refute Enum.any?(names, &(&1 in metrics))
    end

    test "uncategorized rows land under Other, after categorized rows", ctx do
      map_metric("price_usd", ctx.category, ctx.pricing)

      rows = PlanMetricAccess.compute_rows()

      assert %{category: "PMA Test Market", category_slug: "pma-test-market", group: "Pricing"} =
               row_for(rows, "price_usd")

      assert %{category: "Other", category_slug: "other", group: nil} =
               row_for(rows, "volume_usd")

      {categorized, other} = Enum.split_while(rows, &(&1.category != "Other"))
      assert categorized != []
      assert other != []
      assert Enum.all?(other, &(&1.category == "Other"))
    end

    test "a metric whose metadata errors is skipped" do
      mock(Sanbase.Metric, :metadata, fn
        "price_usd" -> {:error, "boom"}
        metric -> :meck.passthrough([metric])
      end)

      rows = PlanMetricAccess.compute_rows()

      refute row_for(rows, "price_usd")
      assert row_for(rows, "price_btc")
    end

    test "variants with diverging access split into separate rows with unique ids" do
      registry = registry!(@template)

      [odd | rest] =
        registry
        |> released_variants()
        |> Enum.filter(&Sanbase.Billing.Plan.AccessChecker.restricted?({:metric, &1}))
        |> Enum.sort()

      assert rest != []

      mock(Sanbase.Billing.Plan.AccessChecker, :restricted?, fn
        {:metric, ^odd} -> false
        query -> :meck.passthrough([query])
      end)

      rows = PlanMetricAccess.compute_rows()

      odd_row = Enum.find(rows, &(&1.id == "r-#{registry.id}-#{odd}"))
      assert odd_row.metrics == [odd]
      assert Enum.all?(odd_row.access, fn {_, access} -> access == {:window, nil, nil} end)

      rest_row = row_for(rows, hd(rest))
      assert rest_row.id == "r-#{registry.id}-#{hd(rest_row.metrics)}"
      refute odd in rest_row.metrics
      refute Enum.any?(rows, &(&1.id == "r-#{registry.id}"))

      assert Enum.uniq_by(rows, & &1.id) == rows
    end

    test "on seeded data, every row id is unique and no registry row is split" do
      rows = PlanMetricAccess.compute_rows()

      assert length(rows) > 100
      assert Enum.uniq_by(rows, & &1.id) == rows
      assert Enum.all?(rows, &(&1.id =~ ~r/^(r-\d+|m-.+)$/))

      metrics = Enum.flat_map(rows, & &1.metrics)
      assert Enum.uniq(metrics) == metrics

      assert Enum.all?(rows, fn row ->
               Map.keys(row) |> Enum.sort() ==
                 [
                   :access,
                   :category,
                   :category_slug,
                   :group,
                   :id,
                   :metrics,
                   :name,
                   :search_text,
                   :variant_names
                 ]
             end)
    end

    test "compute_rows stays fast" do
      {us, _} = :timer.tc(&PlanMetricAccess.compute_rows/0)
      assert us < 2_000_000
    end

    test "rows/0 computes once, then reads the term until expire_cache!/0" do
      PlanMetricAccess.expire_cache!()
      on_exit(&PlanMetricAccess.expire_cache!/0)

      rows = PlanMetricAccess.rows()
      assert rows == PlanMetricAccess.compute_rows()

      # Served from the :persistent_term: nothing is recomputed.
      mock(Sanbase.Metric, :available_metrics, fn -> flunk("recomputed") end)
      assert PlanMetricAccess.rows() == rows

      # Expired: the next read rebuilds.
      :ok = PlanMetricAccess.expire_cache!()
      assert_raise ExUnit.AssertionError, ~r/recomputed/, &PlanMetricAccess.rows/0
    end

    test "a registry refresh expires the rows" do
      on_exit(&PlanMetricAccess.expire_cache!/0)
      _ = PlanMetricAccess.rows()

      :ok = Sanbase.Metric.Registry.refresh_stored_terms()

      mock(Sanbase.Metric, :available_metrics, fn -> flunk("recomputed") end)
      assert_raise ExUnit.AssertionError, ~r/recomputed/, &PlanMetricAccess.rows/0
    end
  end

  defp agrees?({:locked, _}, restriction, _days_ago, _close?),
    do: restriction.is_accessible == false

  # An unrestricted metric (no restricted_from/restricted_to keys at all) is
  # {:window, nil, nil}, as is a restricted one the plan serves in full.
  defp agrees?({:window, history, delay}, restriction, days_ago, close?) do
    restriction.is_accessible and
      close?.(history, days_ago.(Map.get(restriction, :restricted_from))) and
      close?.(delay, days_ago.(Map.get(restriction, :restricted_to)))
  end

  defp registry!(metric) do
    Enum.find(Sanbase.Metric.Registry.all(), &(&1.metric == metric)) ||
      flunk("no registry row #{metric}")
  end

  # Registry stored terms (hidden metrics, deprecation maps, ...) are computed lazily
  # into :persistent_term on first read and outlive the sandbox rollback. Read them
  # all once (compute_rows/0 does) before the DB row changes, so none of them is
  # built from the mutated row and leaks into later tests. Nothing here refreshes
  # the stored terms; the DB change itself rolls back.
  defp update_registry!(registry, changes) do
    _ = PlanMetricAccess.compute_rows()

    registry
    |> Ecto.Changeset.change(changes)
    |> Sanbase.Repo.update!()
  end

  defp released_variants(registry) do
    universe = MapSet.new(Sanbase.Metric.available_metrics())

    registry
    |> Sanbase.Metric.Registry.resolve_registry()
    |> Enum.map(& &1.metric)
    |> Enum.filter(fn metric ->
      metric in universe and
        match?({:ok, %{status: "released"}}, Sanbase.Metric.metadata(metric))
    end)
  end

  defp row_for(rows, metric), do: Enum.find(rows, &(metric in &1.metrics))

  defp map_metric(metric, category, group, module \\ @price_module) do
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

  defp mock_plan_has_access(fun) do
    mock(Sanbase.Billing.Plan.AccessChecker, :plan_has_access?, fun)
  end
end
