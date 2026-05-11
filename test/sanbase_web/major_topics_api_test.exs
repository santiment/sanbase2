defmodule SanbaseWeb.Graphql.MajorTopicsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.MajorTopics

  setup do
    {:ok, conn: build_conn()}
  end

  test "getLatestMajorTopics returns nil when nothing is published", %{conn: conn} do
    result = execute_query(conn, query(), "getLatestMajorTopics")
    assert result == nil
  end

  test "returns the latest published batch in {labels, datasets} shape", %{conn: conn} do
    user = insert(:user)
    {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())
    {:ok, _} = MajorTopics.publish_batch(batch, user.id)

    result = execute_query(conn, query(), "getLatestMajorTopics")

    assert result["intervalStart"] == "2026-05-04"
    assert result["intervalEnd"] == "2026-05-11"
    assert result["labels"] == ["04.05.26", "05.05.26"]

    [d1, d2] = result["datasets"]
    assert d1["label"] == "Bitcoin Reclaims $82K"
    assert d1["topWords"] == "82000,80000,81000"
    assert d1["data"] == [1.0, 3.0]
    assert d1["isCryptoRelevant"] == true
    assert d2["label"] == "Whale Token Activity Alerts"
  end

  defp query do
    """
    {
      getLatestMajorTopics {
        intervalStart
        intervalEnd
        publishedAt
        labels
        datasets {
          label
          topWords
          description
          data
          isCryptoRelevant
        }
      }
    }
    """
  end

  defp sample_payload do
    %{
      source: "twitter_crypto",
      version: 1,
      interval: "2026-05-04T00:00:00/2026-05-11T00:00:00",
      topics: [
        %{
          ch_id: "1;33;twitter_crypto;2026-05-04T00:00:00/2026-05-11T00:00:00;bertopic",
          topic_id: 33,
          title: "Bitcoin Reclaims $82K",
          summary: "BTC reclaims $82K.",
          top_words: "82000,80000,81000",
          is_crypto_relevant: true,
          type: "bertopic",
          values: [
            %{dt: ~U[2026-05-04 00:00:00Z], value: 1.0},
            %{dt: ~U[2026-05-05 00:00:00Z], value: 3.0}
          ]
        },
        %{
          ch_id: "1;34;twitter_crypto;2026-05-04T00:00:00/2026-05-11T00:00:00;bertopic",
          topic_id: 34,
          title: "Whale Token Activity Alerts",
          summary: "Whale activity.",
          top_words: "whale,aped,vol",
          is_crypto_relevant: true,
          type: "bertopic",
          values: [
            %{dt: ~U[2026-05-05 00:00:00Z], value: 2.0}
          ]
        }
      ]
    }
  end
end
