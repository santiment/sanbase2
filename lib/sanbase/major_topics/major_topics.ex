defmodule Sanbase.MajorTopics do
  @moduledoc """
  Context for the "major topics" pipeline: fetch from ClickHouse → moderate in
  admin → publish to GraphQL. See `Sanbase.MajorTopics.TopicBatch` and
  `Sanbase.MajorTopics.MajorTopic`.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.MajorTopics.ClickhouseFetcher
  alias Sanbase.MajorTopics.MajorTopic
  alias Sanbase.MajorTopics.TopicBatch
  alias Sanbase.Repo

  @draft TopicBatch.draft_state()
  @published TopicBatch.published_state()
  @default_granularity TopicBatch.week_granularity()

  @spec list_batches(keyword()) :: [TopicBatch.t()]
  def list_batches(opts \\ []) do
    page = Keyword.get(opts, :page, 1) |> max(1)
    page_size = Keyword.get(opts, :page_size, 50) |> max(1)

    from(b in TopicBatch,
      order_by: [desc: b.fetched_at, desc: b.id],
      limit: ^page_size,
      offset: ^((page - 1) * page_size)
    )
    |> Repo.all()
  end

  @spec count_batches() :: non_neg_integer()
  def count_batches do
    Repo.aggregate(TopicBatch, :count, :id)
  end

  @spec get_batch!(integer()) :: TopicBatch.t()
  def get_batch!(id) do
    TopicBatch
    |> Repo.get!(id)
    |> Repo.preload(topics: from(t in MajorTopic, order_by: [asc: t.position, asc: t.id]))
  end

  @spec latest_published_batch(String.t()) :: TopicBatch.t() | nil
  def latest_published_batch(granularity \\ @default_granularity) do
    from(b in TopicBatch,
      where: b.state == ^@published and b.granularity == ^granularity,
      order_by: [desc: b.interval_start, desc: b.id],
      limit: 1
    )
    |> Repo.one()
    |> preload_active_topics()
  end

  @doc """
  Fetch the published batch at the given `(granularity, interval_start)`. Returns
  `nil` if no such batch exists or is not yet published. Used by the public
  GraphQL field when a frontend navigates via the cursor returned in a previous
  response.
  """
  @spec get_published_batch_at(String.t(), Date.t()) :: TopicBatch.t() | nil
  def get_published_batch_at(granularity, %Date{} = interval_start) do
    from(b in TopicBatch,
      where:
        b.state == ^@published and b.granularity == ^granularity and
          b.interval_start == ^interval_start,
      limit: 1
    )
    |> Repo.one()
    |> preload_active_topics()
  end

  @doc """
  `interval_start` of the immediately-preceding published batch of the same
  granularity, or `nil` when none exists. Used as the `previousIntervalStart`
  cursor in the public GraphQL response.
  """
  @spec previous_published_interval_start(String.t(), Date.t()) :: Date.t() | nil
  def previous_published_interval_start(granularity, %Date{} = current_start) do
    from(b in TopicBatch,
      where:
        b.state == ^@published and b.granularity == ^granularity and
          b.interval_start < ^current_start,
      order_by: [desc: b.interval_start, desc: b.id],
      limit: 1,
      select: b.interval_start
    )
    |> Repo.one()
  end

  @doc """
  `interval_start` of the immediately-following published batch of the same
  granularity, or `nil` when the given batch is already the latest.
  """
  @spec next_published_interval_start(String.t(), Date.t()) :: Date.t() | nil
  def next_published_interval_start(granularity, %Date{} = current_start) do
    from(b in TopicBatch,
      where:
        b.state == ^@published and b.granularity == ^granularity and
          b.interval_start > ^current_start,
      order_by: [asc: b.interval_start, asc: b.id],
      limit: 1,
      select: b.interval_start
    )
    |> Repo.one()
  end

  defp preload_active_topics(nil), do: nil

  defp preload_active_topics(%TopicBatch{} = batch) do
    Repo.preload(batch,
      topics:
        from(t in MajorTopic,
          where: t.is_removed == false,
          order_by: [asc: t.position, asc: t.id]
        )
    )
  end

  @spec get_topic!(integer()) :: MajorTopic.t()
  def get_topic!(id), do: Repo.get!(MajorTopic, id)

  @doc """
  Insert a fresh batch (or replace topics on an existing draft batch) from a
  ClickHouse payload. Idempotent across re-runs while the batch is in `draft`;
  no-op if the batch is already `published`.
  """
  @spec upsert_batch_from_payload(map()) :: {:ok, TopicBatch.t()} | {:error, term()}
  def upsert_batch_from_payload(%{source: source, version: version, interval: interval} = payload) do
    with {:ok, {interval_start, interval_end}} <- parse_interval(interval) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        batch =
          case Repo.get_by(TopicBatch, source: source, interval_text: interval, version: version) do
            nil ->
              attrs = %{
                source: source,
                interval_text: interval,
                interval_start: interval_start,
                interval_end: interval_end,
                version: version,
                type: payload[:type] || derive_type(payload),
                granularity: payload[:granularity] || @default_granularity,
                state: @draft,
                fetched_at: now
              }

              case %TopicBatch{} |> TopicBatch.changeset(attrs) |> Repo.insert() do
                {:ok, batch} -> batch
                {:error, changeset} -> Repo.rollback(changeset)
              end

            existing ->
              existing
          end

        if batch.state == @published do
          batch
        else
          replace_topics(batch, payload.topics)

          case batch |> Ecto.Changeset.change(fetched_at: now) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end
      end)
    end
  end

  defp derive_type(%{topics: [%{type: type} | _]}), do: type
  defp derive_type(_), do: nil

  defp replace_topics(batch, topics) do
    Repo.delete_all(from(t in MajorTopic, where: t.batch_id == ^batch.id))

    Enum.each(Enum.with_index(topics), fn {topic, idx} ->
      attrs = %{
        batch_id: batch.id,
        ch_id: topic.ch_id,
        topic_id: topic.topic_id,
        label: topic.title,
        original_label: topic.title,
        top_words: topic.top_words,
        description: topic.summary || "",
        is_crypto_relevant: topic.is_crypto_relevant,
        position: idx,
        values: serialize_values(Map.get(topic, :values, []))
      }

      case %MajorTopic{} |> MajorTopic.changeset(attrs) |> Repo.insert() do
        {:ok, _} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp serialize_values(values) do
    Enum.map(values, fn
      %{dt: %DateTime{} = dt, value: value} ->
        %{"dt" => DateTime.to_iso8601(dt), "value" => value}

      %{"dt" => _, "value" => _} = entry ->
        entry
    end)
  end

  @spec update_topic(MajorTopic.t(), map()) ::
          {:ok, MajorTopic.t()} | {:error, Ecto.Changeset.t()}
  def update_topic(%MajorTopic{} = topic, attrs) do
    topic
    |> MajorTopic.moderation_changeset(attrs)
    |> Repo.update()
  end

  @spec mark_topic_removed(MajorTopic.t()) :: {:ok, MajorTopic.t()} | {:error, Ecto.Changeset.t()}
  def mark_topic_removed(%MajorTopic{} = topic) do
    update_topic(topic, %{label: topic.label, is_removed: true})
  end

  @spec restore_topic(MajorTopic.t()) :: {:ok, MajorTopic.t()} | {:error, Ecto.Changeset.t()}
  def restore_topic(%MajorTopic{} = topic) do
    update_topic(topic, %{label: topic.label, is_removed: false})
  end

  @doc """
  Transition a draft batch to `published`. Returns `{:error, :already_published}`
  if the batch is not in draft.
  """
  @spec publish_batch(TopicBatch.t(), integer() | nil) ::
          {:ok, TopicBatch.t()} | {:error, :already_published | Ecto.Changeset.t()}
  def publish_batch(%TopicBatch{state: @draft} = batch, user_id) do
    batch
    |> TopicBatch.publish_changeset(user_id)
    |> Repo.update()
  end

  def publish_batch(%TopicBatch{}, _user_id), do: {:error, :already_published}

  @doc """
  Re-query ClickHouse for the given batch and refresh the stored `top_words`
  string on each topic. Only the `top_words` field is touched — `label`,
  `is_removed`, `description`, `position`, and other moderation state are
  preserved.

  Safe to run from a remote console:

      Sanbase.MajorTopics.backfill_top_words(42)

  Returns either `{:error, reason}` or a summary map counting updated /
  unchanged / missing topics.
  """
  @spec backfill_top_words(integer()) ::
          {:ok,
           %{
             topics_updated: non_neg_integer(),
             topics_unchanged: non_neg_integer(),
             topics_missing_in_ch: non_neg_integer(),
             errors: [String.t()]
           }}
          | {:error, term()}
  def backfill_top_words(batch_id) when is_integer(batch_id) do
    case Repo.get(TopicBatch, batch_id) do
      nil ->
        {:error, :batch_not_found}

      batch ->
        with {:ok, by_ch_id} <-
               ClickhouseFetcher.fetch_top_words(batch.source, batch.version, batch.interval_text) do
          summary =
            Repo.all(from(t in MajorTopic, where: t.batch_id == ^batch.id))
            |> Enum.reduce(
              %{topics_updated: 0, topics_unchanged: 0, topics_missing_in_ch: 0, errors: []},
              fn topic, acc ->
                update_topic_top_words(topic, batch, Map.get(by_ch_id, topic.ch_id), acc)
              end
            )

          Logger.info(
            "[backfill_top_words] batch #{batch.id}: #{inspect(Map.delete(summary, :errors))}"
          )

          {:ok, %{summary | errors: Enum.reverse(summary.errors)}}
        end
    end
  end

  defp update_topic_top_words(_topic, _batch, nil, acc) do
    %{acc | topics_missing_in_ch: acc.topics_missing_in_ch + 1}
  end

  defp update_topic_top_words(%MajorTopic{top_words: current} = topic, batch, new, acc) do
    if new == current do
      %{acc | topics_unchanged: acc.topics_unchanged + 1}
    else
      case topic |> Ecto.Changeset.change(top_words: new) |> Repo.update() do
        {:ok, _} ->
          %{acc | topics_updated: acc.topics_updated + 1}

        {:error, cs} ->
          msg = "topic #{topic.id} (batch #{batch.id}): #{inspect(cs.errors)}"
          Logger.error("[backfill_top_words] #{msg}")
          %{acc | errors: [msg | acc.errors]}
      end
    end
  end

  # interval looks like "2026-05-04T00:00:00/2026-05-11T00:00:00"
  defp parse_interval(interval) when is_binary(interval) do
    with [start_str, end_str] <- String.split(interval, "/", parts: 2),
         {:ok, start_date} <- parse_date(start_str),
         {:ok, end_date} <- parse_date(end_str) do
      {:ok, {start_date, end_date}}
    else
      _ -> {:error, "Invalid interval format: #{inspect(interval)}"}
    end
  end

  defp parse_interval(other), do: {:error, "Invalid interval format: #{inspect(other)}"}

  defp parse_date(str) do
    str
    |> String.split("T", parts: 2)
    |> List.first()
    |> Date.from_iso8601()
  end
end
