defmodule Sanbase.Metric.CatalogTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricRegistryHelpers, only: [create_registry_metric: 1]

  alias Sanbase.Metric.Catalog

  test "includes code metrics not present in the registry" do
    entry = Catalog.all_metrics() |> Enum.find(&(&1.metric == "price_usd"))

    assert %{
             source_type: "code",
             source_display: "MetricAdapter",
             source_id: nil,
             module: "Sanbase.Price.MetricAdapter",
             parameters_count: 0,
             variants_count: 1
           } = entry
  end

  test "registry template metrics appear once with variants count from parameters" do
    registry =
      create_registry_metric(%{
        metric: "catalog_tpl_{{param}}",
        internal_metric: "catalog_tpl_internal_{{param}}",
        human_readable_name: "Catalog Tpl {{param}}",
        parameters: [%{"param" => "aaa"}, %{"param" => "bbb"}]
      })

    assert [entry] = Catalog.all_metrics() |> Enum.filter(&(&1.metric == "catalog_tpl_{{param}}"))

    assert entry.source_type == "registry"
    assert entry.source_display == "Registry"
    assert entry.source_id == registry.id
    assert entry.module == nil
    assert entry.parameters_count == 2
    assert entry.variants_count == 2

    # The expansions are covered by the template entry, not listed separately
    metrics = Catalog.all_metrics() |> Enum.map(& &1.metric)
    refute "catalog_tpl_aaa" in metrics
    refute "catalog_tpl_bbb" in metrics
  end

  test "code metrics covered by a registry row are not duplicated" do
    registry = create_registry_metric(%{metric: "price_usd"})

    assert [entry] = Catalog.all_metrics() |> Enum.filter(&(&1.metric == "price_usd"))
    assert entry.source_type == "registry"
    assert entry.source_id == registry.id
  end

  test "entries are sorted by metric name" do
    metrics = Catalog.all_metrics() |> Enum.map(& &1.metric)
    assert metrics == Enum.sort(metrics)
  end
end
