defmodule Sanbase.Metric.Tag.CacheTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Metric.Tag
  alias Sanbase.Metric.Tag.Cache

  defp create_registry_metric(attrs) do
    defaults = %{
      internal_metric: Map.fetch!(attrs, :metric) <> "_internal",
      human_readable_name: "Human name",
      min_interval: "5m",
      tables: [%{name: "daily_metrics_v2"}],
      default_aggregation: "avg",
      access: "free",
      has_incomplete_data: false,
      data_type: "timeseries"
    }

    {:ok, registry} = Sanbase.Metric.Registry.create(Map.merge(defaults, attrs))
    registry
  end

  test "module/metric mapping resolves to the concrete metric name" do
    {:ok, tag} = Tag.create_tag(%{name: "cache_module_tag"})

    {:ok, _} =
      Tag.create_mapping(%{
        tag_id: tag.id,
        module: "Sanbase.Price.MetricAdapter",
        metric: "price_usd"
      })

    Cache.refresh_stored_terms()

    assert MapSet.member?(Cache.metrics_for_tag("cache_module_tag"), "price_usd")
    assert Cache.tags_for_metric("price_usd") == ["cache_module_tag"]
  end

  test "registry-backed mapping resolves to the metric name and its aliases" do
    registry =
      create_registry_metric(%{
        metric: "cache_aliased_metric",
        aliases: [%{name: "cache_aliased_metric_alias"}]
      })

    {:ok, tag} = Tag.create_tag(%{name: "cache_alias_tag"})
    {:ok, _} = Tag.create_mapping(%{tag_id: tag.id, metric_registry_id: registry.id})

    Cache.refresh_stored_terms()

    metrics = Cache.metrics_for_tag("cache_alias_tag")
    assert MapSet.member?(metrics, "cache_aliased_metric")
    assert MapSet.member?(metrics, "cache_aliased_metric_alias")
  end

  test "registry template mapping resolves to all parameter expansions" do
    registry =
      create_registry_metric(%{
        metric: "cache_tpl_{{param}}",
        internal_metric: "cache_tpl_internal_{{param}}",
        human_readable_name: "Cache Tpl {{param}}",
        parameters: [%{"param" => "aaa"}, %{"param" => "bbb"}]
      })

    assert registry.is_template

    {:ok, tag} = Tag.create_tag(%{name: "cache_tpl_tag"})
    {:ok, _} = Tag.create_mapping(%{tag_id: tag.id, metric_registry_id: registry.id})

    Cache.refresh_stored_terms()

    metrics = Cache.metrics_for_tag("cache_tpl_tag")
    assert MapSet.member?(metrics, "cache_tpl_aaa")
    assert MapSet.member?(metrics, "cache_tpl_bbb")
  end

  test "metrics_for_tags/1 returns the union of the given tags" do
    {:ok, tag_a} = Tag.create_tag(%{name: "union_a"})
    {:ok, tag_b} = Tag.create_tag(%{name: "union_b"})

    {:ok, _} =
      Tag.create_mapping(%{tag_id: tag_a.id, module: "M", metric: "metric_a"})

    {:ok, _} =
      Tag.create_mapping(%{tag_id: tag_b.id, module: "M", metric: "metric_b"})

    Cache.refresh_stored_terms()

    union = Cache.metrics_for_tags(["union_a", "union_b"])
    assert MapSet.member?(union, "metric_a")
    assert MapSet.member?(union, "metric_b")
  end

  test "refresh picks up newly created mappings" do
    {:ok, tag} = Tag.create_tag(%{name: "refresh_tag"})

    Cache.refresh_stored_terms()
    assert MapSet.size(Cache.metrics_for_tag("refresh_tag")) == 0

    {:ok, _} = Tag.create_mapping(%{tag_id: tag.id, module: "M", metric: "late_metric"})
    Cache.refresh_stored_terms()

    assert MapSet.member?(Cache.metrics_for_tag("refresh_tag"), "late_metric")
  end

  test "unknown tag returns an empty set" do
    Cache.refresh_stored_terms()
    assert Cache.metrics_for_tag("does_not_exist") == MapSet.new()
  end
end
