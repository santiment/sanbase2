defmodule Sanbase.AvailableMetricsTaxonomyOrderTest do
  use ExUnit.Case, async: true

  alias Sanbase.AvailableMetrics

  defp metric(name, categories), do: %{metric: name, categories: categories}

  defp categorization(opts) do
    %{
      category_id: opts[:category_id],
      category_name: opts[:category_name],
      category_display_order: opts[:category_display_order],
      group_id: opts[:group_id],
      group_name: opts[:group_name],
      group_display_order: opts[:group_display_order],
      display_order: opts[:display_order]
    }
  end

  defp market(group_name, group_display_order, display_order) do
    categorization(
      category_id: 1,
      category_name: "Market",
      category_display_order: 1,
      group_id: group_display_order,
      group_name: group_name,
      group_display_order: group_display_order,
      display_order: display_order
    )
  end

  test "orders by category, then group, then position inside the group" do
    metrics = [
      metric("social_volume", [
        categorization(
          category_id: 2,
          category_name: "Social",
          category_display_order: 3,
          group_id: 20,
          group_name: "Social Volume",
          group_display_order: 1,
          display_order: 1
        )
      ]),
      metric("volume_usd", [market("Volume", 2, 1)]),
      # Alphabetically first, second inside its group.
      metric("a_price_usd", [market("Pricing", 1, 2)]),
      metric("price_usd", [market("Pricing", 1, 1)])
    ]

    assert AvailableMetrics.sort_by_taxonomy(metrics) |> Enum.map(& &1.metric) ==
             ["price_usd", "a_price_usd", "volume_usd", "social_volume"]
  end

  test "ungrouped metrics come after grouped ones of the same category" do
    metrics = [
      metric("ungrouped", [
        categorization(
          category_id: 1,
          category_name: "Market",
          category_display_order: 1,
          group_id: nil,
          group_name: nil,
          group_display_order: nil,
          display_order: nil
        )
      ]),
      metric("grouped", [market("Volume", 2, 1)])
    ]

    assert AvailableMetrics.sort_by_taxonomy(metrics) |> Enum.map(& &1.metric) ==
             ["grouped", "ungrouped"]
  end

  test "metrics in no category sort last, by name" do
    metrics = [
      metric("zz_uncategorized", []),
      metric("aa_uncategorized", []),
      metric("grouped", [market("Pricing", 1, 1)])
    ]

    assert AvailableMetrics.sort_by_taxonomy(metrics) |> Enum.map(& &1.metric) ==
             ["grouped", "aa_uncategorized", "zz_uncategorized"]
  end

  test "a metric in two groups is placed by the first of them" do
    metrics = [
      metric("sentiment_positive_twitter", [
        market("Regular Sentiment", 9, 3),
        market("Positive Sentiment", 4, 1)
      ]),
      metric("volume_usd", [market("Volume", 6, 1)])
    ]

    assert AvailableMetrics.sort_by_taxonomy(metrics) |> Enum.map(& &1.metric) ==
             ["sentiment_positive_twitter", "volume_usd"]

    assert AvailableMetrics.taxonomy_placement(hd(metrics)) ==
             %{category_name: "Market", group_name: "Positive Sentiment"}
  end

  test "a hidden group never becomes the placement" do
    metric =
      metric("also_sellable", [
        categorization(
          category_id: 2,
          category_name: "Social",
          category_display_order: 3,
          group_id: 21,
          group_name: "Deprecated",
          group_display_order: 1,
          display_order: 1
        ),
        categorization(
          category_id: 2,
          category_name: "Social",
          category_display_order: 3,
          group_id: 20,
          group_name: "Social Volume",
          group_display_order: 5,
          display_order: 2
        )
      ])

    assert AvailableMetrics.taxonomy_placement(metric) ==
             %{category_name: "Social", group_name: "Social Volume"}
  end

  test "falls back to the metric name when nothing is ordered" do
    metrics = [metric("b", []), metric("a", [])]

    assert AvailableMetrics.sort_by_taxonomy(metrics) |> Enum.map(& &1.metric) == ["a", "b"]
  end
end
