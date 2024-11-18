defmodule Sanbase.MetricRegisty.ChangeSuggestionTest do
  use Sanbase.DataCase
  import ExUnit.CaptureLog

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.ChangeSuggestion

  test "creating a change suggestion" do
    assert {:ok, metric} = Sanbase.Metric.Registry.by_name("price_usd_5m", "timeseries")

    assert {:ok, %{id: id, metric_registry_id: metric_registry_id, changes: changes}} =
             ChangeSuggestion.create_change_suggestion(
               metric,
               changes(),
               _note = "Testing purposes",
               _submitted_by = "ivan@santiment.net"
             )

    assert metric_registry_id == metric.id
    assert %{} = ChangeSuggestion.decode_changes(changes)
    assert [%{id: ^id}] = ChangeSuggestion.list_all_submissions()

    # The changes are not applied

    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")

    assert metric.access == "free"
    assert metric.sanbase_min_plan == "free"
    assert metric.is_deprecated == false
    assert deprecation_note == nil
  end

  test "applying a change suggestion" do
    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")

    assert {:ok, struct} =
             ChangeSuggestion.create_change_suggestion(
               metric,
               changes(),
               _note = "Testing purposes",
               _submitted_by = "ivan@santiment.net"
             )

    ChangeSuggestion.apply(struct)
  end

  defp changes() do
    %{
      tables: [%{name: "new_intraday_table"}],
      access: "restricted",
      sanbase_min_plan: "max",
      is_deprecated: true,
      selectors: [%{type: "slug"}, %{type: "slugs"}, %{type: "quote_asset"}],
      required_selectors: [%{type: "slug|slugs|quote_asset"}],
      deprecation_note: "Because reasons."
    }
  end
end
