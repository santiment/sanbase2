defmodule Sanbase.MajorTopicsTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.BatchSerializer
  alias Sanbase.MajorTopics.ClickhouseFetcher
  alias Sanbase.MajorTopics.TopicBatch

  describe "top_words_string/1" do
    test "picks top 5 by score and joins comma-separated" do
      words_score = [
        ~s({"word": "alpha", "score": 0.1}),
        ~s({"word": "beta",  "score": 0.5}),
        ~s({"word": "gamma", "score": 0.3}),
        ~s({"word": "delta", "score": 0.9}),
        ~s({"word": "eps",   "score": 0.4}),
        ~s({"word": "zeta",  "score": 0.05}),
        ~s({"word": "eta",   "score": 0.7})
      ]

      assert ClickhouseFetcher.top_words_string(words_score) == "delta,eta,beta,eps,gamma"
    end

    test "ignores malformed JSON elements" do
      words_score = [
        ~s({"word": "ok", "score": 1.0}),
        "not-json",
        ~s({"score": 0.5})
      ]

      assert ClickhouseFetcher.top_words_string(words_score) == "ok"
    end
  end

  describe "upsert_batch_from_payload/1" do
    test "creates a draft batch with topics" do
      payload = sample_payload()

      assert {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload)
      assert batch.state == "draft"
      assert batch.interval_start == ~D[2026-05-04]
      assert batch.interval_end == ~D[2026-05-11]

      loaded = MajorTopics.get_batch!(batch.id)
      assert length(loaded.topics) == 2

      assert Enum.map(loaded.topics, & &1.label) == [
               "Bitcoin Reclaims $82K",
               "Whale Token Activity Alerts"
             ]

      assert Enum.map(loaded.topics, & &1.original_label) == Enum.map(loaded.topics, & &1.label)
    end

    test "is idempotent on re-run while draft (replaces topics)" do
      payload = sample_payload()
      {:ok, batch1} = MajorTopics.upsert_batch_from_payload(payload)

      updated_payload =
        payload
        |> Map.put(:topics, [hd(payload.topics)])

      {:ok, batch2} = MajorTopics.upsert_batch_from_payload(updated_payload)

      assert batch1.id == batch2.id
      assert length(MajorTopics.get_batch!(batch2.id).topics) == 1
    end

    test "no-op when batch is already published" do
      payload = sample_payload()
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload)
      user = insert(:user)

      {:ok, _published} = MajorTopics.publish_batch(batch, user.id)

      tiny = Map.put(payload, :topics, [])
      {:ok, batch_after} = MajorTopics.upsert_batch_from_payload(tiny)

      assert batch_after.state == "published"
      # topics were NOT cleared
      assert length(MajorTopics.get_batch!(batch_after.id).topics) == 2
    end
  end

  describe "publish_batch/2" do
    test "transitions draft → published" do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())
      user = insert(:user)

      assert {:ok, batch} = MajorTopics.publish_batch(batch, user.id)
      assert batch.state == "published"
      assert batch.published_by_id == user.id
      assert %DateTime{} = batch.published_at
    end

    test "errors when already published" do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())
      user = insert(:user)
      {:ok, batch} = MajorTopics.publish_batch(batch, user.id)

      assert {:error, :already_published} = MajorTopics.publish_batch(batch, user.id)
    end
  end

  describe "moderation" do
    setup do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())
      {:ok, batch: MajorTopics.get_batch!(batch.id)}
    end

    test "update_topic/2 changes the label", %{batch: batch} do
      topic = hd(batch.topics)
      {:ok, updated} = MajorTopics.update_topic(topic, %{label: "BTC ATH"})
      assert updated.label == "BTC ATH"
      assert updated.original_label == "Bitcoin Reclaims $82K"
    end

    test "mark_topic_removed/1 + restore_topic/1 toggle is_removed", %{batch: batch} do
      topic = hd(batch.topics)
      {:ok, removed} = MajorTopics.mark_topic_removed(topic)
      assert removed.is_removed == true
      {:ok, restored} = MajorTopics.restore_topic(removed)
      assert restored.is_removed == false
    end
  end

  describe "latest_published_batch/0" do
    test "returns nil when nothing is published" do
      assert MajorTopics.latest_published_batch() == nil
    end

    test "returns the most recent published batch and excludes removed topics" do
      user = insert(:user)

      {:ok, b1} = MajorTopics.upsert_batch_from_payload(sample_payload())
      {:ok, b1} = MajorTopics.publish_batch(b1, user.id)

      newer =
        sample_payload()
        |> Map.put(:interval, "2026-05-05T00:00:00/2026-05-12T00:00:00")

      {:ok, b2} = MajorTopics.upsert_batch_from_payload(newer)
      [first_topic, _] = MajorTopics.get_batch!(b2.id).topics
      {:ok, _} = MajorTopics.mark_topic_removed(first_topic)
      {:ok, _} = MajorTopics.publish_batch(b2, user.id)

      latest = MajorTopics.latest_published_batch()
      assert latest.id == b2.id
      assert length(latest.topics) == 1
      assert hd(latest.topics).is_removed == false
      refute latest.id == b1.id
    end
  end

  describe "BatchSerializer.to_payload/1" do
    test "produces labels + datasets shape aligned on the union of dts" do
      user = insert(:user)
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())
      {:ok, _} = MajorTopics.publish_batch(batch, user.id)

      payload = batch |> Sanbase.Repo.preload(:topics) |> BatchSerializer.to_payload()

      # 3 distinct dts across the two topics
      assert payload.labels == ["04.05.26", "05.05.26", "06.05.26"]

      [d1, d2] = payload.datasets
      assert d1.label == "Bitcoin Reclaims $82K"
      assert d1.top_words == "82000,80000,81000"
      assert d1.data == [1.0, 3.0, 0.0]
      assert d2.data == [0.0, 2.0, 4.0]
    end

    test "excludes removed topics" do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(sample_payload())
      [t1, _] = MajorTopics.get_batch!(batch.id).topics
      {:ok, _} = MajorTopics.mark_topic_removed(t1)

      payload =
        MajorTopics.get_batch!(batch.id)
        |> BatchSerializer.to_payload()

      assert length(payload.datasets) == 1
      assert hd(payload.datasets).label == "Whale Token Activity Alerts"
    end
  end

  describe "schema state helpers" do
    test "states/0 lists draft and published" do
      assert TopicBatch.states() == ["draft", "published"]
    end
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
          summary: "BTC reclaims $82K and triggers short liquidations.",
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
          summary: "Whales ape into various tokens.",
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
end
