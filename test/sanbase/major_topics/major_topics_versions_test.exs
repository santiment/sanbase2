defmodule Sanbase.MajorTopicsVersionsTest do
  # Mocks ClickhouseRepo globally, so it cannot run async
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.MajorTopicsClickhouseMock, only: [with_clickhouse: 2]

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.ClickhouseFetcher
  alias Sanbase.MajorTopics.TopicBatch

  @interval "2026-09-11T00:00:00/2026-09-18T00:00:00"
  @daily_weekly_scope TopicBatch.daily_weekly_scope()

  describe "ClickhouseFetcher.fetch_latest_batch/1" do
    test "takes the highest version of the latest interval" do
      with_clickhouse(%{@interval => 3}, fn ->
        assert {:ok, payload} = ClickhouseFetcher.fetch_latest_batch()
        assert payload.interval == @interval
        assert payload.version == 3
        assert Enum.map(payload.topics, & &1.title) == ["v3 topic 0", "v3 topic 1"]
        assert [%{value: 1.0}] = hd(payload.topics).values
      end)
    end
  end

  describe "upsert_batch_from_payload/1 with versions" do
    test "bumps the version of a draft batch when a newer version arrives" do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload(1))
      {:ok, updated} = MajorTopics.upsert_batch_from_payload(payload(2))

      assert updated.id == batch.id
      assert updated.version == 2
      assert topic_titles(batch.id) == ["v2 topic 0", "v2 topic 1"]
    end

    test "ignores an older version than the stored one" do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload(2))
      {:ok, same} = MajorTopics.upsert_batch_from_payload(payload(1))

      assert same.id == batch.id
      assert same.version == 2
      assert topic_titles(batch.id) == ["v2 topic 0", "v2 topic 1"]
    end

    test "leaves a published batch untouched when a newer version arrives" do
      batch = published_batch(payload(1))
      {:ok, same} = MajorTopics.upsert_batch_from_payload(payload(2))

      assert same.id == batch.id
      assert same.version == 1
      assert same.state == "published"
      assert topic_titles(batch.id) == ["v1 topic 0", "v1 topic 1"]
    end
  end

  describe "newer_versions_available/1" do
    test "returns only the batches with a higher version in ClickHouse" do
      other_interval = "2026-09-12T00:00:00/2026-09-19T00:00:00"
      {:ok, outdated} = MajorTopics.upsert_batch_from_payload(payload(1))

      {:ok, _current} =
        MajorTopics.upsert_batch_from_payload(%{payload(1) | interval: other_interval})

      with_clickhouse(%{@interval => 2, other_interval => 1}, fn ->
        assert MajorTopics.newer_versions_available(MajorTopics.list_batches()) ==
                 {:ok, %{outdated.id => 2}}
      end)
    end
  end

  describe "refetch_newer_version/2" do
    test "replaces the topics of a published batch and moves it back to draft" do
      batch = published_batch(payload(1))
      [topic | _] = MajorTopics.get_batch!(batch.id).topics
      {:ok, _} = MajorTopics.update_topic(topic, %{label: "Edited"})

      with_clickhouse(%{@interval => 2}, fn ->
        assert {:ok, refetched} = MajorTopics.refetch_newer_version(batch, nil)

        assert refetched.id == batch.id
        assert refetched.version == 2
        assert refetched.state == "draft"
        assert refetched.publication_scope == nil
        assert refetched.published_at == nil
        assert refetched.published_by_id == nil
      end)

      assert topic_titles(batch.id) == ["v2 topic 0", "v2 topic 1"]
      assert Enum.all?(MajorTopics.get_batch!(batch.id).topics, &(&1.label == &1.original_label))
      assert MajorTopics.latest_published_batch("week") == nil
    end

    test "returns :no_newer_version when ClickHouse has the same version" do
      {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload(2))

      with_clickhouse(%{@interval => 2}, fn ->
        assert MajorTopics.refetch_newer_version(batch, nil) == {:error, :no_newer_version}
      end)

      assert MajorTopics.get_batch!(batch.id).version == 2
    end
  end

  defp published_batch(payload) do
    {:ok, batch} = MajorTopics.upsert_batch_from_payload(payload)
    {:ok, batch} = MajorTopics.publish_batch(batch, insert(:user).id, @daily_weekly_scope)
    batch
  end

  defp topic_titles(batch_id) do
    MajorTopics.get_batch!(batch_id).topics |> Enum.map(& &1.original_label)
  end

  defp payload(version) do
    %{
      source: "twitter_crypto",
      version: version,
      interval: @interval,
      topics:
        Enum.map(0..1, fn idx ->
          %{
            ch_id: "#{version};#{idx};twitter_crypto;#{@interval};bertopic",
            topic_id: idx,
            title: "v#{version} topic #{idx}",
            summary: "Summary #{idx}.",
            top_words: "word#{idx}",
            is_crypto_relevant: true,
            type: "bertopic",
            values: [%{dt: ~U[2026-09-11 00:00:00Z], value: 1.0}]
          }
        end)
    }
  end
end
