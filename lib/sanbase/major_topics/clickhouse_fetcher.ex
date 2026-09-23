defmodule Sanbase.MajorTopics.ClickhouseFetcher do
  @moduledoc """
  Reads the daily rolling-window "major topics" snapshot from ClickHouse.

  Source tables: `major_topics_metadata` (one row per topic in an interval) and
  `major_topics_values` (sub-daily timeseries per topic id).
  """

  alias Sanbase.Clickhouse.Query
  alias Sanbase.ClickhouseRepo

  @default_source "twitter_crypto"

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

  @doc """
  Fetch the most recent interval for `source`, at the highest version stored
  for that interval. A higher version is a recalculation of the same interval
  and always supersedes the lower ones.
  """
  @spec fetch_latest_batch(keyword()) :: {:ok, payload()} | {:error, String.t()}
  def fetch_latest_batch(opts \\ []) do
    source = Keyword.get(opts, :source, @default_source)

    with {:ok, interval} <- fetch_latest_interval(source),
         {:ok, version} when is_integer(version) <- fetch_latest_version(source, interval) do
      fetch_batch(source, version, interval)
    else
      {:ok, nil} -> {:error, "No major_topics_metadata rows for source=#{source}"}
      {:error, _} = err -> err
    end
  end

  @doc """
  Fetch the full payload (metadata + values) for an exact
  `(source, version, interval)`.
  """
  @spec fetch_batch(String.t(), integer(), String.t()) :: {:ok, payload()} | {:error, term()}
  def fetch_batch(source, version, interval) do
    with {:ok, [_ | _] = metadata} <- fetch_metadata(source, version, interval),
         {:ok, values_by_id} <- fetch_values(Enum.map(metadata, & &1.ch_id)) do
      topics =
        Enum.map(metadata, fn row ->
          Map.put(row, :values, Map.get(values_by_id, row.ch_id, []))
        end)

      {:ok, %{source: source, version: version, interval: interval, topics: topics}}
    else
      {:ok, []} ->
        {:error,
         "No major_topics_metadata rows for source=#{source} version=#{version} interval=#{interval}"}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Highest version stored for `(source, interval)`, or `nil` when the interval
  has no rows.
  """
  @spec fetch_latest_version(String.t(), String.t()) :: {:ok, integer() | nil} | {:error, term()}
  def fetch_latest_version(source, interval) do
    case fetch_latest_versions(source, [interval]) do
      {:ok, versions} -> {:ok, Map.get(versions, interval)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Highest version stored for each of `intervals`, as `%{interval => version}`.
  Intervals without rows are absent from the map.
  """
  @spec fetch_latest_versions(String.t(), [String.t()]) ::
          {:ok, %{String.t() => integer()}} | {:error, term()}
  def fetch_latest_versions(_source, []), do: {:ok, %{}}

  def fetch_latest_versions(source, intervals) do
    sql = """
    SELECT interval, max(version)
    FROM major_topics_metadata
    WHERE source = {{source}} AND interval IN ({{intervals}})
    GROUP BY interval
    """

    query = Query.new(sql, %{source: source, intervals: intervals})

    ClickhouseRepo.query_reduce(query, %{}, fn [interval, version], acc ->
      Map.put(acc, interval, version)
    end)
  end

  defp fetch_latest_interval(source) do
    sql = """
    SELECT max(interval)
    FROM major_topics_metadata
    WHERE source = {{source}}
    """

    query = Query.new(sql, %{source: source})

    case ClickhouseRepo.query_reduce(query, nil, fn [interval], _acc -> interval end) do
      {:ok, interval} when is_binary(interval) and interval != "" ->
        {:ok, interval}

      {:ok, _} ->
        {:error, "No major_topics_metadata rows for source=#{source}"}

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
