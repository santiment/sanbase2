defmodule Sanbase.Metric.Category.CacheTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricRegistryHelpers, only: [create_registry_metric: 1]
  import Sanbase.MetricVersionAliasHelpers, only: [create_category!: 1]

  alias Sanbase.Repo
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.Cache
  alias Sanbase.Metric.Category.MetricCategory

  setup do
    Cache.clear()
    :ok
  end

  test "a metric in no category is {:ok, []}, distinct from a load failure" do
    assert {:ok, []} = Cache.category_ids_for_metric("no_such_metric_at_all")
  end

  test "module/metric mapping resolves to the concrete metric name" do
    category = create_category!("Cache Module")

    {:ok, _} =
      Category.create_mapping(%{
        category_id: category.id,
        module: "Sanbase.Price.MetricAdapter",
        metric: "price_usd"
      })

    assert {:ok, [category.id]} == Cache.category_ids_for_metric("price_usd")
  end

  test "registry-backed mapping resolves to the metric name and its public aliases" do
    registry =
      create_registry_metric(%{
        metric: "cache_cat_aliased_metric",
        aliases: [%{name: "cache_cat_aliased_metric_alias"}]
      })

    category = create_category!("Cache Alias")

    {:ok, _} =
      Category.create_mapping(%{category_id: category.id, metric_registry_id: registry.id})

    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_cat_aliased_metric")
    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_cat_aliased_metric_alias")
  end

  test "registry template mapping resolves to every parameter expansion" do
    registry =
      create_registry_metric(%{
        metric: "cache_cat_tpl_{{param}}",
        internal_metric: "cache_cat_tpl_internal_{{param}}",
        human_readable_name: "Cache Cat Tpl {{param}}",
        parameters: [%{"param" => "aaa"}, %{"param" => "bbb"}]
      })

    assert registry.is_template

    category = create_category!("Cache Template")

    {:ok, _} =
      Category.create_mapping(%{category_id: category.id, metric_registry_id: registry.id})

    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_cat_tpl_aaa")
    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_cat_tpl_bbb")
  end

  test "a metric in several categories lists each id once" do
    first = create_category!("Cache Multi A")
    second = create_category!("Cache Multi B")

    for category <- [first, second] do
      {:ok, _} =
        Category.create_mapping(%{
          category_id: category.id,
          module: "Sanbase.Clickhouse.MetricAdapter",
          metric: "cache_multi_metric"
        })
    end

    assert {:ok, ids} = Cache.category_ids_for_metric("cache_multi_metric")
    assert Enum.sort(ids) == Enum.sort([first.id, second.id])
  end

  test "deleting a group or a category clears the cache, as their mappings go by cascade" do
    category = create_category!("Cache Cascade")

    {:ok, group} =
      Category.create_group(%{name: "Cascade Group", category_id: category.id, display_order: 1})

    {:ok, _} =
      Category.create_mapping(%{
        category_id: category.id,
        group_id: group.id,
        module: "Sanbase.Clickhouse.MetricAdapter",
        metric: "cache_cascade_metric"
      })

    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_cascade_metric")

    {:ok, _} = Category.delete_group(group)
    assert {:ok, []} = Cache.category_ids_for_metric("cache_cascade_metric")

    {:ok, _} =
      Category.create_mapping(%{
        category_id: category.id,
        module: "Sanbase.Clickhouse.MetricAdapter",
        metric: "cache_cascade_metric"
      })

    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_cascade_metric")

    {:ok, _} = Category.delete_category(category)
    assert {:ok, []} = Cache.category_ids_for_metric("cache_cascade_metric")
  end

  test "the map is cached until it is cleared; the Category context clears it on writes" do
    category = create_category!("Cache Staleness")
    assert {:ok, []} = Cache.category_ids_for_metric("cache_stale_metric")

    # Written behind the context's back: the cached map does not see it ...
    Repo.insert!(%Category.MetricCategoryMapping{
      category_id: category.id,
      module: "Sanbase.Clickhouse.MetricAdapter",
      metric: "cache_stale_metric"
    })

    assert {:ok, []} = Cache.category_ids_for_metric("cache_stale_metric")

    # ... until cleared.
    Cache.clear()
    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_stale_metric")

    # Writes through the context clear it themselves.
    {:ok, _} =
      Category.create_mapping(%{
        category_id: category.id,
        module: "Sanbase.Clickhouse.MetricAdapter",
        metric: "cache_stale_metric_2"
      })

    assert {:ok, [category.id]} == Cache.category_ids_for_metric("cache_stale_metric_2")
  end
end
