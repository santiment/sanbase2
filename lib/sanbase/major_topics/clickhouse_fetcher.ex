defmodule Sanbase.MajorTopics.ClickhouseFetcher do
  @moduledoc """
  Reads the daily rolling-window "major topics" snapshot from ClickHouse.

  Source tables: `major_topics_metadata` (one row per topic in an interval) and
  `major_topics_values` (sub-daily timeseries per topic id).
  """

  alias Sanbase.Clickhouse.Query
  alias Sanbase.ClickhouseRepo

  @default_source "twitter_crypto"
  @default_version 1

  @type topic :: %{
          ch_id: String.t(),
          topic_id: integer(),
          title: String.t(),
          summary: String.t(),
          top_words: String.t(),
          is_crypto_relevant: boolean(),
          type: String.t(),
          values: [%{dt: DateTime.t(), value: float()}]
        }

  @type payload :: %{
          source: String.t(),
          version: integer(),
          interval: String.t(),
          topics: [topic()]
        }

  @doc """
  Re-query the metadata table for a specific `(source, version, interval)` and
  return `%{ch_id => top_words_string}` using the current top-words selection
  rules. Used by `Sanbase.MajorTopics.backfill_top_words/1` to refresh stored
  top words on historical batches without touching moderation state.
  """
  @spec fetch_top_words(String.t(), integer(), String.t()) ::
          {:ok, %{String.t() => String.t()}} | {:error, term()}
  def fetch_top_words(source, version, interval) do
    case fetch_metadata(source, version, interval) do
      {:ok, rows} -> {:ok, Map.new(rows, fn row -> {row.ch_id, row.top_words} end)}
      {:error, _} = err -> err
    end
  end

  @spec fetch_latest_batch(keyword()) :: {:ok, payload()} | {:error, String.t()}
  def fetch_latest_batch(opts \\ []) do
    source = Keyword.get(opts, :source, @default_source)
    version = Keyword.get(opts, :version, @default_version)

    with {:ok, interval} <- fetch_latest_interval(source, version),
         {:ok, metadata} <- fetch_metadata(source, version, interval),
         {:ok, values_by_id} <- fetch_values(Enum.map(metadata, & &1.ch_id)) do
      topics =
        Enum.map(metadata, fn row ->
          Map.put(row, :values, Map.get(values_by_id, row.ch_id, []))
        end)

      {:ok, %{source: source, version: version, interval: interval, topics: topics}}
    end
  end

  defp fetch_latest_interval(source, version) do
    sql = """
    SELECT max(interval)
    FROM major_topics_metadata
    WHERE source = {{source}} AND version = {{version}}
    """

    query = Query.new(sql, %{source: source, version: version})

    case ClickhouseRepo.query_reduce(query, nil, fn [interval], _acc -> interval end) do
      {:ok, nil} ->
        {:error, "No major_topics_metadata rows for source=#{source} version=#{version}"}

      {:ok, ""} ->
        {:error, "No major_topics_metadata rows for source=#{source} version=#{version}"}

      {:ok, interval} when is_binary(interval) ->
        {:ok, interval}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_metadata(source, version, interval) do
    sql = """
    SELECT id, topic_id, title, summary, is_crypto_relevant, type, words_score
    FROM major_topics_metadata
    WHERE source = {{source}}
      AND version = {{version}}
      AND interval = {{interval}}
    ORDER BY topic_id ASC
    """

    query = Query.new(sql, %{source: source, version: version, interval: interval})

    ClickhouseRepo.query_reduce(query, [], fn row, acc ->
      [parse_metadata_row(row) | acc]
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, _} = err -> err
    end
  end

  defp parse_metadata_row([
         ch_id,
         topic_id,
         title,
         summary,
         is_crypto_relevant,
         type,
         words_score
       ]) do
    %{
      ch_id: ch_id,
      topic_id: topic_id,
      title: title,
      summary: summary,
      top_words: top_words_string(words_score),
      is_crypto_relevant: !!is_crypto_relevant,
      type: type
    }
  end

  @doc """
  Pick the 10 highest-scoring words from a `words_score` Array(String) where each
  element is a JSON-encoded `{"word", "score"}` map; join into a comma-separated
  string. Public so tests can exercise it without ClickHouse access.
  """
  @spec top_words_string([String.t()]) :: String.t()
  def top_words_string(words_score) when is_list(words_score) do
    words_score
    |> Enum.flat_map(fn json ->
      case Jason.decode(json) do
        {:ok, %{"word" => word, "score" => score}} -> [{word, score}]
        _ -> []
      end
    end)
    |> Enum.sort_by(fn {_word, score} -> score end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn {word, _score} -> word end)
    |> Enum.join(",")
  end

  defp fetch_values([]), do: {:ok, %{}}

  defp fetch_values(ids) do
    sql = """
    SELECT id, value, toUnixTimestamp(dt)
    FROM major_topics_values
    WHERE id IN ({{ids}})
    ORDER BY id, dt
    """

    query = Query.new(sql, %{ids: ids})

    ClickhouseRepo.query_reduce(query, %{}, fn [id, value, dt_unix], acc ->
      entry = %{dt: DateTime.from_unix!(dt_unix), value: value * 1.0}
      Map.update(acc, id, [entry], fn list -> [entry | list] end)
    end)
    |> case do
      {:ok, grouped} -> {:ok, Map.new(grouped, fn {k, v} -> {k, Enum.reverse(v)} end)}
      {:error, _} = err -> err
    end
  end
end
