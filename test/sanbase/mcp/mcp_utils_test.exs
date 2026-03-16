defmodule Sanbase.MCPUtilsTest do
  use ExUnit.Case, async: false

  alias Sanbase.MCP.Utils

  doctest(Sanbase.MCP.Utils)

  test "truncate_response keeps total_count aligned with insights" do
    insights =
      for id <- 1..50 do
        %{
          id: id,
          title: "Insight #{id}",
          text: String.duplicate("x", 3_000)
        }
      end

    response =
      Utils.truncate_response(%{
        insights: insights,
        total_count: length(insights),
        requested_ids: Enum.to_list(1..50)
      })

    assert response.truncated
    assert response.total_count == length(response.insights)
    assert response.total_count < length(insights)
  end

  test "truncate_response keeps named count fields aligned with lists" do
    metrics =
      for id <- 1..80 do
        %{
          name: "metric_#{id}",
          description: String.duplicate("m", 1_500)
        }
      end

    assets =
      for id <- 1..80 do
        %{
          slug: "asset-#{id}",
          description: String.duplicate("a", 1_500)
        }
      end

    response =
      Utils.truncate_response(%{
        metrics: metrics,
        assets: assets,
        metrics_count: length(metrics),
        assets_count: length(assets)
      })

    assert response.truncated
    assert response.metrics_count == length(response.metrics)
    assert response.assets_count == length(response.assets)
    assert response.metrics_count < length(metrics) or response.assets_count < length(assets)
  end

  test "truncate_response trims nested datapoint lists before top-level slugs" do
    slugs = for id <- 1..10, do: "asset-#{id}"

    data =
      Map.new(slugs, fn slug ->
        datapoints =
          for hour <- 1..120 do
            %{
              datetime: "2025-01-#{rem(hour, 28) + 1}T00:00:00Z",
              value: hour,
              note: String.duplicate("#{slug}-", 150)
            }
          end

        {slug, datapoints}
      end)

    response =
      Utils.truncate_response(%{
        metric: "price_usd",
        slugs: slugs,
        data: data,
        period: "Since 2025-01-01T00:00:00Z",
        interval: "1h"
      })

    assert response.truncated
    assert response.slugs == slugs
    assert Enum.sort(Map.keys(response.data)) == Enum.sort(slugs)
    assert Enum.any?(response.data, fn {_slug, datapoints} -> length(datapoints) < 120 end)
  end

  test "truncate_response drops oversized data map entries and keeps slugs in sync" do
    slugs = for id <- 1..4_000, do: "asset-#{id}"

    data =
      Map.new(slugs, fn slug ->
        {slug, [%{datetime: "2025-01-01T00:00:00Z", value: 1}]}
      end)

    response =
      Utils.truncate_response(%{
        metric: "price_usd",
        slugs: slugs,
        data: data,
        period: "Since 2025-01-01T00:00:00Z",
        interval: "1d"
      })

    assert response.truncated
    assert length(response.slugs) < length(slugs)
    assert Enum.sort(response.slugs) == Enum.sort(Map.keys(response.data))
  end

  test "truncate_response trims nested trends payloads before metadata" do
    trends =
      for id <- 1..100 do
        %{
          word: "word_#{id}",
          documents_summary: String.duplicate("summary-", 500)
        }
      end

    response =
      Utils.truncate_response(%{
        trends: %{
          trending_words: trends,
          trending_stories: []
        },
        metadata: %{
          included_data_types: ["stories", "words"]
        },
        errors: []
      })

    assert response.truncated
    assert length(response.trends.trending_words) < length(trends)
    assert response.metadata.included_data_types == ["stories", "words"]
  end
end
