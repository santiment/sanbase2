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

  describe "docs filter" do
    setup do
      %{
        metrics: [
          %{metric: "documented", docs: [%{link: "https://example.com"}], categories: []},
          %{metric: "undocumented", docs: [], categories: []}
        ]
      }
    end

    test "with", %{metrics: metrics} do
      assert filtered(metrics, %{"docs" => "with"}) == ["documented"]
    end

    test "without", %{metrics: metrics} do
      assert filtered(metrics, %{"docs" => "without"}) == ["undocumented"]
    end

    test "all", %{metrics: metrics} do
      assert filtered(metrics, %{"docs" => "all"}) == ["documented", "undocumented"]
    end

    test "no docs filter at all leaves both", %{metrics: metrics} do
      assert filtered(metrics, %{}) == ["documented", "undocumented"]
    end

    test "the old only_with_docs checkbox still filters", %{metrics: metrics} do
      assert filtered(metrics, %{"only_with_docs" => "on"}) == ["documented"]
    end
  end

  defp filtered(metrics, filter) do
    AvailableMetrics.apply_filters(metrics, filter) |> Enum.map(& &1.metric)
  end

  test "hides metrics that only live in a hidden group" do
    metrics = [
      metric("social_volume_twitter_news", [
        %{category_id: 2, category_name: "Social", group_id: 21, group_name: "Deprecated"}
      ]),
      metric("mentions_count_reddit", [
        %{category_id: 2, category_name: "Social", group_id: 22, group_name: "Internal Metrics"}
      ]),
      metric("also_sellable", [
        %{category_id: 2, category_name: "Social", group_id: 21, group_name: "Deprecated"},
        %{category_id: 2, category_name: "Social", group_id: 20, group_name: "Social Volume"}
      ])
    ]

    result =
      AvailableMetrics.apply_filters(metrics, %{})
      |> Enum.map(& &1.metric)

    assert result == ["also_sellable"]
  end

  test "hides hidden metrics and the ones the API already refuses" do
    metrics = [
      metric("live", []),
      # Still serves data, with no end date, so it stays in the inventory even
      # though it can no longer be sold.
      metric("soft_deprecated", []) |> Map.put(:is_deprecated, true),
      # Works until the date, so it is still listed.
      metric("scheduled", []) |> Map.put(:hard_deprecate_after, ~U[2100-01-01 00:00:00Z]),
      # Every request fails - listing it would advertise an error.
      metric("hard_deprecated", []) |> Map.put(:hard_deprecate_after, ~U[2020-01-01 00:00:00Z]),
      metric("internal", []) |> Map.put(:is_hidden, true)
    ]

    assert AvailableMetrics.apply_filters(metrics, %{}) |> Enum.map(& &1.metric) ==
             ["live", "soft_deprecated", "scheduled"]
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
