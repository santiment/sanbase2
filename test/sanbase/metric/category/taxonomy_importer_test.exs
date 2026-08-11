defmodule Sanbase.Metric.Category.TaxonomyImporterTest do
  @moduledoc ~s"""
  The importer rewrites the group of ~933 mapping rows on production, so the
  cases worth pinning are the destructive ones, not the happy path:

    * the ungrouped row must be deleted once the metric is grouped, or it shows
      up twice in the API and once under "Ungrouped"
    * dual membership must produce a second row, not overwrite the first
    * a re-run must change nothing
    * dissolving an old group must refuse when a metric in it would be dropped
    * a move must leave nothing behind in the source category, or the metric
      stays sellable through the source package
  """

  use Sanbase.DataCase, async: false

  import ExUnit.CaptureIO, only: [with_io: 1]

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.MetricGroup
  alias Sanbase.Metric.Category.TaxonomyImporter
  alias Sanbase.MetricRegistryHelpers
  alias Sanbase.Repo

  setup do
    {:ok, market} = MetricCategory.create(%{name: "TaxTest Market", display_order: 1})
    {:ok, labels} = MetricCategory.create(%{name: "TaxTest Labels", display_order: 2})

    %{market: market, labels: labels}
  end

  describe "the checked-in specs" do
    test "every spec names a category, groups with unique names, and no metric twice in a group" do
      for name <- TaxonomyImporter.specs() do
        plan = quietly(fn -> TaxonomyImporter.plan([name]) end) |> hd()
        spec = plan.spec

        assert is_binary(spec.category) and spec.category != ""

        group_names = Enum.map(spec.groups, & &1.name)
        assert group_names == Enum.uniq(group_names), "#{name}: duplicate group name"

        for group <- spec.groups do
          assert group.metrics == Enum.uniq(group.metrics),
                 "#{name}/#{group.name}: duplicate metric"
        end

        # Title Case throughout, matching the group names that predate this work
        # (Network Activity, Social Dominance, Top Holders). The Notion pages mix
        # cases; the database convention wins.
        for group <- spec.groups do
          assert group.name =~ ~r/^[A-Z]/, "#{name}: #{group.name} does not start capitalised"

          # Every word capitalised, except the function words "and" and "&".
          # Acronyms (NFT, ETF, MVRV, DEXes, XRPL, AI) satisfy this as written.
          refute group.name =~ ~r/ (?!and\b|&)[a-z]/,
                 "#{name}: #{group.name} is not Title Case"
        end

        # An `also` target must be a group of its own, or the roll-up row would
        # have nowhere to go.
        alsos = spec.groups |> Enum.flat_map(&Map.get(&1, :also, [])) |> Enum.uniq()
        assert alsos -- group_names == [], "#{name}: `also` names a group that does not exist"
      end
    end

    test "refuses a spec whose category does not exist" do
      for %MetricCategory{} = category <- Repo.all(MetricCategory), do: Repo.delete!(category)

      plans = quietly(fn -> TaxonomyImporter.plan(["market"]) end)

      assert [%{error: error}] = plans
      assert error =~ "Market"
      assert error =~ "does not exist"
    end

    test "raises on an unknown spec name" do
      assert_raise ArgumentError, ~r/Unknown spec/, fn -> TaxonomyImporter.plan(["nope"]) end
    end
  end

  describe "apply_spec!/2" do
    test "creates the groups in spec order and groups the metrics", %{market: market} do
      ungrouped("tax_price_usd", market)
      ungrouped("tax_volume_usd", market)

      spec = %{
        category: market.name,
        groups: [
          %{name: "Pricing", metrics: ["tax_price_usd"]},
          %{name: "Volume", metrics: ["tax_volume_usd"]}
        ]
      }

      assert :ok = TaxonomyImporter.apply_spec!("fixture", spec)

      assert [%{name: "Pricing", display_order: 1}, %{name: "Volume", display_order: 2}] =
               MetricGroup.list_by_category(market.id)

      assert group_of("tax_price_usd", market) == "Pricing"
      assert group_of("tax_volume_usd", market) == "Volume"
    end

    test "deletes the ungrouped row once the metric is grouped", %{market: market} do
      ungrouped("tax_price_usd", market)

      apply_fixture(market, [%{name: "Pricing", metrics: ["tax_price_usd"]}])

      rows = rows_for("tax_price_usd", market)

      assert length(rows) == 1
      refute Enum.any?(rows, &is_nil(&1.group_id))
    end

    test "a metric in a group and a roll-up gets one row per group", %{market: market} do
      ungrouped("tax_sentiment_positive", market)

      apply_fixture(market, [
        %{name: "Regular Sentiment", metrics: [], rollup: true},
        %{
          name: "Positive Sentiment",
          also: ["Regular Sentiment"],
          metrics: ["tax_sentiment_positive"]
        }
      ])

      assert groups_of("tax_sentiment_positive", market) == [
               "Positive Sentiment",
               "Regular Sentiment"
             ]
    end

    test "is a no-op on a second run", %{market: market} do
      ungrouped("tax_price_usd", market)
      groups = [%{name: "Pricing", metrics: ["tax_price_usd"]}]

      apply_fixture(market, groups)
      before = snapshot(market)

      apply_fixture(market, groups)

      assert snapshot(market) == before
    end

    test "skips a metric that has no mapping row in the category", %{market: market} do
      ungrouped("tax_price_usd", market)

      plan =
        TaxonomyImporter.plan_spec("fixture", %{
          category: market.name,
          groups: [%{name: "Pricing", metrics: ["tax_price_usd", "tax_typo_metric"]}]
        })

      assert plan.unknown == ["tax_typo_metric"]

      apply_fixture(market, [%{name: "Pricing", metrics: ["tax_price_usd", "tax_typo_metric"]}])

      assert group_of("tax_price_usd", market) == "Pricing"
      assert rows_for("tax_typo_metric", market) == []
    end

    test "keeps a grouped row the spec does not ask for, and reports it", %{market: market} do
      # An admin may have added it deliberately. Deleting it would revoke access
      # somebody paid for.
      {:ok, keep} = MetricGroup.create(%{name: "Keep", category_id: market.id, display_order: 9})
      registry = MetricRegistryHelpers.create_registry_metric("tax_price_usd")

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: market.id,
          group_id: keep.id
        })

      plan =
        TaxonomyImporter.plan_spec("fixture", %{
          category: market.name,
          groups: [%{name: "Pricing", metrics: []}]
        })

      assert Enum.map(plan.extra, & &1.id) == [hd(rows_for("tax_price_usd", market)).id]

      apply_fixture(market, [%{name: "Pricing", metrics: []}])

      assert groups_of("tax_price_usd", market) == ["Keep"]
    end

    test "renames an existing group instead of creating a second one", %{market: market} do
      ungrouped("tax_dex_volume", market)
      {:ok, old} = MetricGroup.create(%{name: "XRP", category_id: market.id, display_order: 1})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: MetricRegistryHelpers.create_registry_metric("tax_xrp_old").id,
          category_id: market.id,
          group_id: old.id
        })

      TaxonomyImporter.apply_spec!("fixture", %{
        category: market.name,
        groups: [%{name: "XRPL Chain", metrics: ["tax_dex_volume"]}],
        rename_groups: %{"XRP" => "XRPL Chain"}
      })

      assert [%MetricGroup{id: id, name: "XRPL Chain"}] = MetricGroup.list_by_category(market.id)
      assert id == old.id
      # The metric that was already in the group is still in it.
      assert groups_of("tax_xrp_old", market) == ["XRPL Chain"]
      assert groups_of("tax_dex_volume", market) == ["XRPL Chain"]
    end
  end

  describe "dissolving an old group" do
    test "deletes it once every metric in it is placed elsewhere", %{market: market} do
      {:ok, old} =
        MetricGroup.create(%{name: "Total sentiment", category_id: market.id, display_order: 1})

      registry = MetricRegistryHelpers.create_registry_metric("tax_sentiment_total")

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: market.id,
          group_id: old.id
        })

      TaxonomyImporter.apply_spec!("fixture", %{
        category: market.name,
        groups: [%{name: "Positive Sentiment", metrics: ["tax_sentiment_total"]}],
        delete_groups: ["Total sentiment"]
      })

      assert Enum.map(MetricGroup.list_by_category(market.id), & &1.name) == [
               "Positive Sentiment"
             ]

      assert groups_of("tax_sentiment_total", market) == ["Positive Sentiment"]
    end

    test "refuses when a metric in it is not placed anywhere", %{market: market} do
      {:ok, old} =
        MetricGroup.create(%{name: "Total sentiment", category_id: market.id, display_order: 1})

      registry = MetricRegistryHelpers.create_registry_metric("tax_orphan")

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: market.id,
          group_id: old.id
        })

      spec = %{
        category: market.name,
        groups: [%{name: "Positive Sentiment", metrics: []}],
        delete_groups: ["Total sentiment"]
      }

      assert [%{orphans: ["tax_orphan"]}] =
               TaxonomyImporter.plan_spec("fixture", spec).group_deletions

      TaxonomyImporter.apply_spec!("fixture", spec)

      assert "Total sentiment" in Enum.map(MetricGroup.list_by_category(market.id), & &1.name)
      assert groups_of("tax_orphan", market) == ["Total sentiment"]
    end
  end

  describe "display_order" do
    test "gives no two groups in a category the same order", %{market: market} do
      # A group the spec neither lists nor dissolves keeps its old order, which
      # collided with a spec group's until it was pushed past the spec's range.
      {:ok, _} =
        MetricGroup.create(%{name: "Euler", category_id: market.id, display_order: 1})

      apply_fixture(market, [
        %{name: "Pricing", metrics: []},
        %{name: "Volume", metrics: []}
      ])

      orders = MetricGroup.list_by_category(market.id) |> Enum.map(& &1.display_order)

      assert orders == Enum.uniq(orders)
      assert MetricGroup.get_by_name_and_category("Euler", market.id).display_order == 3
    end

    test "gives no two rows in a group the same order", %{market: market} do
      {:ok, group} =
        MetricGroup.create(%{name: "Top Holders", category_id: market.id, display_order: 1})

      # A surviving unrequested row and a spec-listed one both at 1.
      for metric <- ["tax_kept_row", "tax_listed_row"] do
        {:ok, _} =
          MetricCategoryMapping.create(%{
            metric_registry_id: MetricRegistryHelpers.create_registry_metric(metric).id,
            category_id: market.id,
            group_id: group.id,
            display_order: 1
          })
      end

      apply_fixture(market, [%{name: "Top Holders", metrics: ["tax_listed_row"]}])

      rows = Repo.all(MetricCategoryMapping) |> Enum.filter(&(&1.group_id == group.id))
      orders = Enum.map(rows, & &1.display_order)

      assert Enum.sort(orders) == [1, 2]
      # The spec-listed metric comes first; the survivor is parked after it.
      assert Enum.find(rows, &(&1.display_order == 1))
             |> Repo.preload(:metric_registry)
             |> then(& &1.metric_registry.metric) ==
               "tax_listed_row"
    end
  end

  describe "unplaced metrics" do
    test "reports an ungrouped row the spec never names", %{market: market} do
      ungrouped("tax_price_usd", market)
      ungrouped("tax_forgotten", market)

      plan =
        TaxonomyImporter.plan_spec("fixture", %{
          category: market.name,
          groups: [%{name: "Pricing", metrics: ["tax_price_usd"]}]
        })

      # Neither `unknown` (a spec name with no row) nor `extra` (a grouped row the
      # spec did not ask for) would have shown this one.
      assert plan.unplaced == ["tax_forgotten"]
      assert plan.unknown == []
      assert plan.extra == []

      apply_fixture(market, [%{name: "Pricing", metrics: ["tax_price_usd"]}])

      # Left ungrouped rather than guessed at.
      assert groups_of("tax_forgotten", market) == []
    end

    test "does not count a metric that is leaving via `moves`", %{
      market: market,
      labels: labels
    } do
      ungrouped("tax_nft_market_volume", market)
      {:ok, _} = MetricGroup.create(%{name: "NFT", category_id: labels.id, display_order: 1})

      plan =
        TaxonomyImporter.plan_spec("fixture", %{
          category: market.name,
          groups: [%{name: "Pricing", metrics: []}],
          moves: [
            %{metric: "tax_nft_market_volume", to_category: labels.name, to_group: "NFT"}
          ]
        })

      # It is leaving the category, not forgotten in it.
      assert plan.unplaced == []
    end

    test "names it in the report, not only counts it" do
      # A count alone sends the reader back to SQL to find out which metric it
      # was - which is how two Market metrics went unnoticed on stage.
      {:ok, market} = MetricCategory.create(%{name: "Market", display_order: 9})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: MetricRegistryHelpers.create_registry_metric("tax_not_in_spec").id,
          category_id: market.id
        })

      {_plans, output} = with_io(fn -> TaxonomyImporter.plan(["market"]) end)

      assert output =~ "unplaced metrics:    1"
      assert output =~ "tax_not_in_spec"
    end
  end

  describe "remove_from_groups" do
    test "removes the row from a kept group once the metric is placed elsewhere", %{
      market: market
    } do
      {:ok, kept} =
        MetricGroup.create(%{name: "Top Holders", category_id: market.id, display_order: 1})

      registry = MetricRegistryHelpers.create_registry_metric("tax_whale_count")

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: market.id,
          group_id: kept.id
        })

      TaxonomyImporter.apply_spec!("fixture", %{
        category: market.name,
        groups: [
          %{name: "Top Holders", metrics: []},
          %{name: "Whales", metrics: ["tax_whale_count"]}
        ],
        remove_from_groups: %{"Top Holders" => ["tax_whale_count"]}
      })

      # One row, in the new group - not one in each.
      assert groups_of("tax_whale_count", market) == ["Whales"]
      assert "Top Holders" in Enum.map(MetricGroup.list_by_category(market.id), & &1.name)
    end

    test "refuses when the spec places the metric nowhere else", %{market: market} do
      {:ok, kept} =
        MetricGroup.create(%{name: "Top Holders", category_id: market.id, display_order: 1})

      registry = MetricRegistryHelpers.create_registry_metric("tax_only_here")

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: market.id,
          group_id: kept.id
        })

      spec = %{
        category: market.name,
        groups: [%{name: "Top Holders", metrics: []}],
        remove_from_groups: %{"Top Holders" => ["tax_only_here"]}
      }

      assert [%{placed?: false}] = TaxonomyImporter.plan_spec("fixture", spec).row_removals

      TaxonomyImporter.apply_spec!("fixture", spec)

      # Removing it would have been the last row it had.
      assert groups_of("tax_only_here", market) == ["Top Holders"]
    end
  end

  describe "moves" do
    test "leaves nothing behind in the source category", %{market: market, labels: labels} do
      ungrouped("tax_nft_market_volume", market)
      {:ok, nft} = MetricGroup.create(%{name: "NFT", category_id: labels.id, display_order: 1})

      TaxonomyImporter.apply_spec!("fixture", %{
        category: market.name,
        groups: [%{name: "Pricing", metrics: []}],
        moves: [
          %{metric: "tax_nft_market_volume", to_category: labels.name, to_group: "NFT"}
        ]
      })

      assert rows_for("tax_nft_market_volume", market) == []
      assert [%{group_id: group_id}] = rows_for("tax_nft_market_volume", labels)
      assert group_id == nft.id
    end

    test "the destination spec claims the moved row, so it gets an order", %{
      market: market,
      labels: labels
    } do
      # A move creates a row in the target group. If the target spec does not also
      # list the metric, that row belongs to no group the spec claims: no
      # display_order, and reported as unrequested on every later run.
      ungrouped("tax_nft_market_volume", market)

      TaxonomyImporter.apply_spec!("labels", %{
        category: labels.name,
        groups: [%{name: "NFT", metrics: ["tax_nft_market_volume"]}]
      })

      TaxonomyImporter.apply_spec!("market", %{
        category: market.name,
        groups: [%{name: "Pricing", metrics: []}],
        moves: [
          %{metric: "tax_nft_market_volume", to_category: labels.name, to_group: "NFT"}
        ]
      })

      # Second pass, now that the row is in the target category.
      TaxonomyImporter.apply_spec!("labels", %{
        category: labels.name,
        groups: [%{name: "NFT", metrics: ["tax_nft_market_volume"]}]
      })

      plan =
        TaxonomyImporter.plan_spec("labels", %{
          category: labels.name,
          groups: [%{name: "NFT", metrics: ["tax_nft_market_volume"]}]
        })

      assert plan.extra == []
      assert [%{display_order: 1}] = rows_for("tax_nft_market_volume", labels)
    end

    test "a moved row is parked after the last row of the target group", %{
      market: market,
      labels: labels
    } do
      # Without this the row keeps the order it had in the group it left, which
      # collides with whatever holds that number in the target group.
      ungrouped("tax_nft_market_volume", market)

      TaxonomyImporter.apply_spec!("labels", %{
        category: labels.name,
        groups: [%{name: "NFT", metrics: []}]
      })

      nft = MetricGroup.get_by_name_and_category("NFT", labels.id)

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: MetricRegistryHelpers.create_registry_metric("tax_nft_resident").id,
          category_id: labels.id,
          group_id: nft.id,
          display_order: 1
        })

      TaxonomyImporter.apply_spec!("market", %{
        category: market.name,
        groups: [%{name: "Pricing", metrics: []}],
        moves: [
          %{metric: "tax_nft_market_volume", to_category: labels.name, to_group: "NFT"}
        ]
      })

      assert [%{display_order: 2}] = rows_for("tax_nft_market_volume", labels)
    end

    test "a group whose metrics all move out is dissolved", %{market: market, labels: labels} do
      # Euler and Morpho: the group's metrics belong to another category, so
      # "placed elsewhere" means moved, not regrouped.
      {:ok, euler} =
        MetricGroup.create(%{name: "Euler", category_id: market.id, display_order: 1})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: MetricRegistryHelpers.create_registry_metric("tax_euler_apy").id,
          category_id: market.id,
          group_id: euler.id
        })

      {:ok, lending} =
        MetricGroup.create(%{name: "Lending", category_id: labels.id, display_order: 1})

      spec = %{
        category: market.name,
        groups: [%{name: "Pricing", metrics: []}],
        delete_groups: ["Euler"],
        moves: [%{metric: "tax_euler_apy", to_category: labels.name, to_group: "Lending"}]
      }

      assert [%{orphans: []}] = TaxonomyImporter.plan_spec("fixture", spec).group_deletions

      TaxonomyImporter.apply_spec!("fixture", spec)

      refute "Euler" in Enum.map(MetricGroup.list_by_category(market.id), & &1.name)
      assert rows_for("tax_euler_apy", market) == []
      assert [%{group_id: group_id}] = rows_for("tax_euler_apy", labels)
      assert group_id == lending.id
    end

    test "a dissolve still refuses when only some of the group moves", %{
      market: market,
      labels: labels
    } do
      {:ok, euler} =
        MetricGroup.create(%{name: "Euler", category_id: market.id, display_order: 1})

      for metric <- ["tax_euler_apy", "tax_euler_stays"] do
        {:ok, _} =
          MetricCategoryMapping.create(%{
            metric_registry_id: MetricRegistryHelpers.create_registry_metric(metric).id,
            category_id: market.id,
            group_id: euler.id
          })
      end

      {:ok, _} = MetricGroup.create(%{name: "Lending", category_id: labels.id, display_order: 1})

      spec = %{
        category: market.name,
        groups: [%{name: "Pricing", metrics: []}],
        delete_groups: ["Euler"],
        moves: [%{metric: "tax_euler_apy", to_category: labels.name, to_group: "Lending"}]
      }

      assert [%{orphans: ["tax_euler_stays"]}] =
               TaxonomyImporter.plan_spec("fixture", spec).group_deletions

      TaxonomyImporter.apply_spec!("fixture", spec)

      # The move still happens; the group survives with the metric that has
      # nowhere to go, rather than dropping it.
      assert "Euler" in Enum.map(MetricGroup.list_by_category(market.id), & &1.name)
      assert rows_for("tax_euler_apy", market) == []
      assert groups_of("tax_euler_stays", market) == ["Euler"]
    end

    test "refuses when the target group does not exist yet", %{market: market, labels: labels} do
      ungrouped("tax_nft_market_volume", market)

      spec = %{
        category: market.name,
        groups: [%{name: "Pricing", metrics: []}],
        moves: [%{metric: "tax_nft_market_volume", to_category: labels.name, to_group: "NFT"}]
      }

      assert [%{target_group: nil}] = TaxonomyImporter.plan_spec("fixture", spec).moves

      TaxonomyImporter.apply_spec!("fixture", spec)

      # The row stays where it was rather than being deleted or half-moved.
      assert [%{group_id: nil}] = rows_for("tax_nft_market_volume", market)
    end
  end

  describe "code metrics and templates" do
    test "groups a metric served by an adapter module", %{market: market} do
      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Price.MetricAdapter",
          metric: "tax_code_metric",
          category_id: market.id
        })

      apply_fixture(market, [%{name: "Pricing", metrics: ["tax_code_metric"]}])

      assert [row] = rows_for("tax_code_metric", market)
      assert row.module == "Sanbase.Price.MetricAdapter"
      assert group_of("tax_code_metric", market) == "Pricing"
    end

    test "groups a template by its unexpanded name", %{market: market} do
      registry =
        MetricRegistryHelpers.create_registry_metric(%{
          metric: "tax_price_change_{{interval}}",
          internal_metric: "tax_price_change_{{interval}}_internal",
          is_template: true,
          parameters: [%{"interval" => "1d"}, %{"interval" => "7d"}]
        })

      {:ok, _} =
        MetricCategoryMapping.create(%{
          metric_registry_id: registry.id,
          category_id: market.id
        })

      apply_fixture(market, [%{name: "Pricing", metrics: ["tax_price_change_{{interval}}"]}])

      assert group_of("tax_price_change_{{interval}}", market) == "Pricing"
    end
  end

  describe "category order" do
    test "renumbers the taxonomy's categories and leaves the others alone" do
      # The five real categories are what @category_display_order names; the two
      # from `setup` are not in it and must keep their order.
      for {name, display_order} <- Enum.with_index(real_categories(), 40) do
        {:ok, _} =
          MetricCategory.create_if_not_exists(%{name: name, display_order: display_order})
      end

      quietly(fn -> TaxonomyImporter.apply_category_order!() end)

      ordered =
        MetricCategory.list_ordered()
        |> Enum.map(& &1.name)
        |> Enum.filter(&(&1 in real_categories()))

      assert ordered == real_categories()

      assert MetricCategory.get_by_name("TaxTest Market").display_order == 1
      assert MetricCategory.get_by_name("TaxTest Labels").display_order == 2
    end

    test "is a no-op on a second run" do
      for {name, display_order} <- Enum.with_index(real_categories(), 1) do
        {:ok, _} =
          MetricCategory.create_if_not_exists(%{name: name, display_order: display_order})
      end

      output = with_io(fn -> TaxonomyImporter.apply_category_order!() end) |> elem(1)

      assert output =~ "category order: already correct"
    end
  end

  # ------------------------------------------------------------------ helpers

  defp real_categories,
    do: ["Market", "Development", "Social", "On-chain", "On-chain Labels"]

  defp apply_fixture(category, groups) do
    TaxonomyImporter.apply_spec!("fixture", %{category: category.name, groups: groups})
  end

  defp ungrouped(metric, category) do
    registry = MetricRegistryHelpers.create_registry_metric(metric)

    {:ok, mapping} =
      MetricCategoryMapping.create(%{
        metric_registry_id: registry.id,
        category_id: category.id
      })

    mapping
  end

  defp rows_for(metric, category) do
    Repo.all(MetricCategoryMapping)
    |> Repo.preload(:metric_registry)
    |> Enum.filter(fn row ->
      row.category_id == category.id and
        (row.metric == metric or (row.metric_registry && row.metric_registry.metric == metric))
    end)
  end

  defp groups_of(metric, category) do
    names = Map.new(MetricGroup.list_by_category(category.id), &{&1.id, &1.name})

    metric
    |> rows_for(category)
    |> Enum.map(&names[&1.group_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp group_of(metric, category), do: metric |> groups_of(category) |> hd()

  defp snapshot(category) do
    Repo.all(MetricCategoryMapping)
    |> Enum.filter(&(&1.category_id == category.id))
    |> Enum.map(&{&1.id, &1.group_id, &1.display_order})
    |> Enum.sort()
  end

  # The importer reports to stdout; the tests assert on the plan it returns.
  defp quietly(fun), do: with_io(fun) |> elem(0)
end
