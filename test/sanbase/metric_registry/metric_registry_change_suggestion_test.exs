defmodule Sanbase.MetricRegisty.MetricRegistryChangeSuggestionTest do
  use Sanbase.DataCase

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.ChangeSuggestion

  @moduletag capture_log: true

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
    assert metric.deprecation_note == nil
  end

  test "accepting a change suggestion updates the metric" do
    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")

    assert metric.is_verified == true
    assert metric.sync_status == "synced"

    assert {:ok, struct} =
             ChangeSuggestion.create_change_suggestion(
               metric,
               changes(),
               _note = "Testing purposes",
               _submitted_by = "ivan@santiment.net"
             )

    # Creating a change suggestion does not change the metric is_verified and sync_status
    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")
    assert metric.is_verified == true
    assert metric.sync_status == "synced"
    assert {:ok, _} = ChangeSuggestion.update_status(struct.id, "approved")

    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")

    assert metric.access == "restricted"
    assert metric.sanbase_min_plan == "max"
    assert metric.is_deprecated == true
    assert metric.deprecation_note == "Because reasons."
    assert metric.selectors |> Enum.map(&Map.get(&1, :type)) == ["slug", "slugs", "quote_asset"]
    assert metric.required_selectors |> hd() |> Map.get(:type) == "slug|slugs|quote_asset"
    assert metric.tables |> hd() |> Map.get(:name) == "new_intraday_table"

    # Approving a change puts the metric in a unverified and unsynced state
    assert metric.is_verified == false
    assert metric.sync_status == "not_synced"
  end

  test "declining a change suggestion does not update the metric" do
    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")

    assert {:ok, struct} =
             ChangeSuggestion.create_change_suggestion(
               metric,
               changes(),
               _note = "Testing purposes",
               _submitted_by = "ivan@santiment.net"
             )

    assert {:ok, _} = ChangeSuggestion.update_status(struct.id, "declined")

    assert {:ok, metric} = Registry.by_name("price_usd_5m", "timeseries")

    assert metric.access == "free"
    assert metric.sanbase_min_plan == "free"
    assert metric.is_deprecated == false
    assert metric.deprecation_note == nil
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
