defmodule Sanbase.MajorTopics.BatchSerializer do
  @moduledoc """
  Convert a `TopicBatch` (with its topics preloaded) into the
  `{labels, datasets}` shape consumed by the social-trends frontend and the
  public GraphQL `majorTopicsBatch` query.
  """

  alias Sanbase.MajorTopics.MajorTopic
  alias Sanbase.MajorTopics.TopicBatch

  @label_format "%d.%m.%y"

  @type dataset :: %{
          label: String.t(),
          top_words: String.t(),
          description: String.t(),
          data: [float()],
          is_crypto_relevant: boolean()
        }

  @type payload :: %{
          granularity: String.t(),
          interval_start: Date.t(),
          interval_end: Date.t(),
          published_at: DateTime.t() | nil,
          labels: [String.t()],
          datasets: [dataset()],
          previous_interval_start: Date.t() | nil,
          next_interval_start: Date.t() | nil
        }

  @doc """
  Build the payload for a single `TopicBatch`. Pagination cursors default to
  `nil`; the resolver supplies them by querying for sibling batches.
  """
  @spec to_payload(TopicBatch.t(), keyword()) :: payload()
  def to_payload(%TopicBatch{topics: topics} = batch, opts \\ []) when is_list(topics) do
    active = Enum.reject(topics, & &1.is_removed)

    limited =
      active
      |> Enum.sort_by(& &1.position)
      |> take_topics(Keyword.get(opts, :limit))

    dts = collect_dts(limited)
    labels = Enum.map(dts, &Calendar.strftime(&1, @label_format))
    datasets = Enum.map(limited, &topic_to_dataset(&1, dts))

    %{
      granularity: Keyword.fetch!(opts, :granularity),
      interval_start: batch.interval_start,
      interval_end: batch.interval_end,
      published_at: batch.published_at,
      labels: labels,
      datasets: datasets,
      previous_interval_start: Keyword.get(opts, :previous_interval_start),
      next_interval_start: Keyword.get(opts, :next_interval_start)
    }
  end

  defp take_topics(topics, nil), do: topics

  defp take_topics(topics, limit) when is_integer(limit) and limit > 0,
    do: Enum.take(topics, limit)

  defp take_topics(topics, _), do: topics

  defp collect_dts(topics) do
    topics
    |> Enum.flat_map(&Enum.map(&1.values, fn entry -> parse_dt(entry["dt"]) end))
    |> Enum.uniq()
    |> Enum.sort(DateTime)
  end

  defp topic_to_dataset(%MajorTopic{} = topic, dts) do
    by_dt =
      Map.new(topic.values, fn entry ->
        {parse_dt(entry["dt"]), entry["value"] * 1.0}
      end)

    data = Enum.map(dts, fn dt -> Map.get(by_dt, dt, 0.0) end)

    %{
      label: topic.label,
      top_words: topic.top_words,
      description: topic.description,
      data: data,
      is_crypto_relevant: topic.is_crypto_relevant
    }
  end

  defp parse_dt(%DateTime{} = dt), do: dt

  defp parse_dt(iso) when is_binary(iso) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    dt
  end
end
