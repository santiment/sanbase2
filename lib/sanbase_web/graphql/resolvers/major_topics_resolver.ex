defmodule SanbaseWeb.Graphql.Resolvers.MajorTopicsResolver do
  @moduledoc false

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.BatchSerializer
  alias Sanbase.MajorTopics.TopicBatch

  @default_granularity TopicBatch.week_granularity()
  @default_limit 20

  def get_latest_published(_root, _args, _resolution) do
    fetch_and_wrap(@default_granularity, nil, @default_limit)
  end

  def get_major_topics_batch(_root, args, _resolution) do
    granularity = Map.get(args, :granularity, @default_granularity)
    interval_start = Map.get(args, :interval_start)
    limit = Map.get(args, :limit, @default_limit)

    fetch_and_wrap(granularity, interval_start, limit)
  end

  defp fetch_and_wrap(granularity, nil, limit) do
    MajorTopics.latest_published_batch()
    |> wrap_with_cursors(granularity, limit)
  end

  defp fetch_and_wrap(granularity, %Date{} = interval_start, limit) do
    MajorTopics.get_published_batch_at(interval_start)
    |> wrap_with_cursors(granularity, limit)
  end

  defp wrap_with_cursors(nil, _granularity, _limit), do: {:ok, nil}

  defp wrap_with_cursors(batch, granularity, limit) do
    opts = [
      granularity: granularity,
      limit: limit,
      previous_interval_start:
        MajorTopics.previous_published_interval_start(granularity, batch.interval_start),
      next_interval_start:
        MajorTopics.next_published_interval_start(granularity, batch.interval_start)
    ]

    {:ok, BatchSerializer.to_payload(batch, opts)}
  end
end
