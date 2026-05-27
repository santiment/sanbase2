defmodule SanbaseWeb.Graphql.MajorTopicsApiTest do
  use SanbaseWeb.ConnCase, async: true

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.MajorTopics

  setup do
    {:ok, conn: build_conn(), user: insert(:user)}
  end

  describe "majorTopicsBatch" do
    test "returns nil when nothing is published", %{conn: conn} do
      assert execute_query(conn, batch_query(granularity: "WEEK"), "majorTopicsBatch") == nil
      assert execute_query(conn, batch_query(granularity: "DAY"), "majorTopicsBatch") == nil
    end

    test "returns the latest published batch when no intervalStart is given", %{
      conn: conn,
      user: user
    } do
      publish(payload_for("2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)
      latest = publish(payload_for("2026-05-11T00:00:00/2026-05-18T00:00:00"), user.id)

      result = execute_query(conn, batch_query(granularity: "WEEK"), "majorTopicsBatch")

      assert result["granularity"] == "WEEK"
      assert result["intervalStart"] == Date.to_iso8601(latest.interval_start)
      assert result["intervalEnd"] == Date.to_iso8601(latest.interval_end)
      assert result["previousIntervalStart"] == "2026-05-04"
      assert result["nextIntervalStart"] == nil
    end

    test "returns the batch keyed by intervalStart cursor", %{conn: conn, user: user} do
      publish(payload_for("2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)
      publish(payload_for("2026-05-11T00:00:00/2026-05-18T00:00:00"), user.id)
      publish(payload_for("2026-05-18T00:00:00/2026-05-25T00:00:00"), user.id)

      result =
        execute_query(
          conn,
          batch_query(granularity: "WEEK", interval_start: "2026-05-11"),
          "majorTopicsBatch"
        )

      assert result["intervalStart"] == "2026-05-11"
      assert result["previousIntervalStart"] == "2026-05-04"
      assert result["nextIntervalStart"] == "2026-05-18"
    end

    test "returns nil for an intervalStart with no published batch", %{conn: conn, user: user} do
      publish(payload_for("2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)

      result =
        execute_query(
          conn,
          batch_query(granularity: "WEEK", interval_start: "2026-01-01"),
          "majorTopicsBatch"
        )

      assert result == nil
    end

    test "granularity affects pagination step only, not which batch is returned", %{
      conn: conn,
      user: user
    } do
      publish(payload_for("2026-04-30T00:00:00/2026-05-07T00:00:00"), user.id)
      publish(payload_for("2026-05-07T00:00:00/2026-05-14T00:00:00"), user.id)
      publish(payload_for("2026-05-08T00:00:00/2026-05-15T00:00:00"), user.id)

      week =
        execute_query(
          conn,
          batch_query(granularity: "WEEK", interval_start: "2026-05-08"),
          "majorTopicsBatch"
        )

      day =
        execute_query(
          conn,
          batch_query(granularity: "DAY", interval_start: "2026-05-08"),
          "majorTopicsBatch"
        )

      assert week["intervalStart"] == "2026-05-08"
      assert day["intervalStart"] == "2026-05-08"
      assert week["granularity"] == "WEEK"
      assert day["granularity"] == "DAY"
      assert week["previousIntervalStart"] == "2026-04-30"
      assert day["previousIntervalStart"] == "2026-05-07"
    end

    test "carries the {labels, datasets} payload", %{conn: conn, user: user} do
      publish(payload_for("2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)

      result = execute_query(conn, batch_query(granularity: "WEEK"), "majorTopicsBatch")

      assert result["labels"] == ["04.05.26", "05.05.26", "06.05.26"]
      [d1, d2] = result["datasets"]
      assert d1["label"] == "Bitcoin Reclaims $82K"
      assert d1["topWords"] == "82000,80000,81000"
      assert d1["data"] == [1.0, 3.0, 0.0]
      assert d2["data"] == [0.0, 2.0, 4.0]
    end

    test "defaults limit to 20 datasets", %{conn: conn, user: user} do
      publish(payload_with_topic_count(25, "2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)

      result = execute_query(conn, batch_query(granularity: "WEEK"), "majorTopicsBatch")

      assert length(result["datasets"]) == 20
      assert hd(result["datasets"])["label"] == "Topic 0"
      assert List.last(result["datasets"])["label"] == "Topic 19"
    end

    test "accepts explicit limit", %{conn: conn, user: user} do
      publish(payload_with_topic_count(25, "2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)

      result =
        execute_query(
          conn,
          batch_query(granularity: "WEEK", limit: 5),
          "majorTopicsBatch"
        )

      assert length(result["datasets"]) == 5
      assert Enum.map(result["datasets"], & &1["label"]) == Enum.map(0..4, &"Topic #{&1}")
    end
  end

  describe "getLatestMajorTopics (deprecated)" do
    test "returns nil when nothing is published", %{conn: conn} do
      assert execute_query(conn, legacy_query(), "getLatestMajorTopics") == nil
    end

    test "delegates to weekly granularity", %{conn: conn, user: user} do
      publish(payload_for("2026-05-04T00:00:00/2026-05-11T00:00:00"), user.id)

      result = execute_query(conn, legacy_query(), "getLatestMajorTopics")

      assert result["intervalStart"] == "2026-05-04"
      assert result["intervalEnd"] == "2026-05-11"
      assert result["granularity"] == "WEEK"
    end
  end

  defp publish(payload, user_id) do
    {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload)
    {:ok, batch} = MajorTopics.publish_batch(batch, user_id)
    batch
  end

  defp payload_with_topic_count(count, interval) do
    topics =
      Enum.map(0..(count - 1), fn idx ->
        %{
          ch_id: "1;#{idx};twitter_crypto;#{interval};bertopic",
          topic_id: idx,
          title: "Topic #{idx}",
          summary: "Summary #{idx}.",
          top_words: "word#{idx}",
          is_crypto_relevant: true,
          type: "bertopic",
          values: [%{dt: ~U[2026-05-04 00:00:00Z], value: idx * 1.0}]
        }
      end)

    %{
      source: "twitter_crypto",
      version: 1,
      interval: interval,
      topics: topics
    }
  end

  defp payload_for(interval) do
    %{
      source: "twitter_crypto",
      version: 1,
      interval: interval,
      topics: [
        %{
          ch_id: "1;33;twitter_crypto;#{interval};bertopic",
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
          ch_id: "1;34;twitter_crypto;#{interval};bertopic",
          topic_id: 34,
          title: "Whale Token Activity Alerts",
          summary: "Whale activity.",
          top_words: "whale,aped,vol",
          is_crypto_relevant: true,
          type: "bertopic",
          values: [
            %{dt: ~U[2026-05-05 00:00:00Z], value: 2.0},
            %{dt: ~U[2026-05-06 00:00:00Z], value: 4.0}
          ]
        }
      ]
    }
  end

  defp batch_query(opts) do
    granularity = Keyword.fetch!(opts, :granularity)
    interval_start = Keyword.get(opts, :interval_start)
    limit = Keyword.get(opts, :limit)

    args =
      ["granularity: #{granularity}"]
      |> then(fn acc ->
        case interval_start do
          nil -> acc
          v -> acc ++ [~s|intervalStart: "#{v}"|]
        end
      end)
      |> then(fn acc ->
        case limit do
          nil -> acc
          v -> acc ++ ["limit: #{v}"]
        end
      end)
      |> Enum.join(", ")

    """
    {
      majorTopicsBatch(#{args}) {
        granularity
        intervalStart
        intervalEnd
        publishedAt
        labels
        previousIntervalStart
        nextIntervalStart
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

  defp legacy_query do
    """
    {
      getLatestMajorTopics {
        granularity
        intervalStart
        intervalEnd
        publishedAt
        labels
        datasets {
          label
          topWords
          data
        }
      }
    }
    """
  end
end
