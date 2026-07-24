defmodule Sanbase.AvailableMetricsCategorizationFilterTest do
  use ExUnit.Case, async: true

  alias Sanbase.AvailableMetrics

  defp metric(name, categories) do
    %{
      metric: name,
      internal_name: name,
      docs: [%{link: "https://example.com"}],
      available_assets: ["bitcoin"],
      available_selectors: [:slug],
      frequency_seconds: 86_400,
      categories: categories
    }
  end

  setup do
    metrics = [
      metric("price_usd", [
        %{category_id: 1, category_name: "Market", group_id: 10, group_name: "Pricing"}
      ]),
      metric("volume_usd", [
        %{category_id: 1, category_name: "Market", group_id: 11, group_name: "Volume"}
      ]),
      metric("social_volume", [
        %{category_id: 2, category_name: "Social", group_id: 20, group_name: "Social Volume"}
      ]),
      metric("ungrouped_market", [
        %{category_id: 1, category_name: "Market", group_id: nil, group_name: nil}
      ]),
      metric("uncategorized_metric", [])
    ]

    %{metrics: metrics}
  end

  test "filters by category", %{metrics: metrics} do
    result =
      AvailableMetrics.apply_filters(metrics, %{"category_id" => "1"})
      |> Enum.map(& &1.metric)
      |> Enum.sort()

    assert result == ["price_usd", "ungrouped_market", "volume_usd"]
  end

  test "filters by category and group", %{metrics: metrics} do
    result =
      AvailableMetrics.apply_filters(metrics, %{"category_id" => "1", "group_id" => "10"})
      |> Enum.map(& &1.metric)

    assert result == ["price_usd"]
  end

  test "filters uncategorized metrics", %{metrics: metrics} do
    result =
      AvailableMetrics.apply_filters(metrics, %{"category_id" => "none"})
      |> Enum.map(& &1.metric)

    assert result == ["uncategorized_metric"]
  end

  test "filters ungrouped metrics within a category", %{metrics: metrics} do
    result =
      AvailableMetrics.apply_filters(metrics, %{"category_id" => "1", "group_id" => "none"})
      |> Enum.map(& &1.metric)

    assert result == ["ungrouped_market"]
  end

  test "does not match category and group across different mappings" do
    metrics = [
      metric("multi", [
        %{category_id: 1, category_name: "Market", group_id: 10, group_name: "Pricing"},
        %{category_id: 2, category_name: "Social", group_id: 20, group_name: "Social Volume"}
      ])
    ]

    result =
      AvailableMetrics.apply_filters(metrics, %{"category_id" => "1", "group_id" => "20"})
      |> Enum.map(& &1.metric)

    assert result == []
  end
end
