defmodule Sanbase.MajorTopics.LegacySeed do
  @moduledoc """
  One-off importer for historical major-topics batches that lived in the
  sanbase-app frontend repo as `data-<N>.ts` modules. Each JSON file under
  `priv/repo/major_topics_seed/` becomes one published weekly batch with
  `source: "legacy-frontend"` and `version: <N>`.

  Run from a remote console after the JSON files are deployed:

      Sanbase.MajorTopics.LegacySeed.run()

  Idempotent — existing `(source, version)` batches are skipped. The seed
  directory, JSON files, and this module are intended to be removed in a
  follow-up PR once the import is verified in production.
  """

  require Logger

  alias Sanbase.MajorTopics.MajorTopic
  alias Sanbase.MajorTopics.TopicBatch
  alias Sanbase.Repo

  @source "legacy-frontend"
  @granularity TopicBatch.week_granularity()

  # Files using "MMM DD, HH:MM" labels don't encode the year. Determined by
  # matching neighboring files' weeks.
  @year_overrides %{1 => 2023, 2 => 2024}

  @month_map %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  def seed_dir do
    Path.join([:code.priv_dir(:sanbase), "repo", "major_topics_seed"])
  end

  @spec run() :: map()
  def run do
    files =
      seed_dir()
      |> File.ls!()
      |> Enum.filter(&String.match?(&1, ~r/^data-\d+\.json$/))
      |> Enum.sort_by(&file_number/1)

    Logger.info("[legacy_seed] importing #{length(files)} files from #{seed_dir()}")

    summary = %{inserted: 0, skipped: 0, failed: 0, errors: []}

    Enum.reduce(files, summary, fn file, acc ->
      version = file_number(file)

      case import_file(Path.join(seed_dir(), file), version) do
        :ok ->
          %{acc | inserted: acc.inserted + 1}

        :skipped ->
          %{acc | skipped: acc.skipped + 1}

        {:error, reason} ->
          Logger.error("[legacy_seed] failed #{file}: #{inspect(reason)}")
          %{acc | failed: acc.failed + 1, errors: [{file, reason} | acc.errors]}
      end
    end)
    |> tap(fn s ->
      Logger.info("[legacy_seed] done: #{inspect(Map.delete(s, :errors))}")
    end)
  end

  defp file_number(name) do
    [_, n] = Regex.run(~r/data-(\d+)/, name)
    String.to_integer(n)
  end

  defp import_file(path, version) do
    case Repo.get_by(TopicBatch, source: @source, version: version) do
      %TopicBatch{} ->
        :skipped

      nil ->
        with {:ok, raw} <- File.read(path),
             {:ok, payload} <- Jason.decode(raw),
             {:ok, parsed} <- parse_payload(payload, version) do
          insert_batch(parsed, version)
        end
    end
  end

  defp insert_batch(parsed, version) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      batch_attrs = %{
        source: @source,
        interval_text: "#{parsed.interval_start}/#{parsed.interval_end}",
        interval_start: parsed.interval_start,
        interval_end: parsed.interval_end,
        version: version,
        type: "legacy",
        granularity: @granularity,
        state: TopicBatch.published_state(),
        fetched_at: now
      }

      batch =
        %TopicBatch{}
        |> TopicBatch.changeset(batch_attrs)
        |> Ecto.Changeset.put_change(:published_at, now)
        |> Repo.insert!()

      Enum.with_index(parsed.topics)
      |> Enum.each(fn {topic, idx} ->
        %MajorTopic{}
        |> MajorTopic.changeset(%{
          batch_id: batch.id,
          ch_id: "legacy-#{version}-#{idx}",
          topic_id: idx,
          label: topic.label,
          original_label: topic.label,
          top_words: topic.top_words,
          description: topic.description,
          is_crypto_relevant: true,
          position: idx,
          values: topic.values
        })
        |> Repo.insert!()
      end)

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_payload(%{"labels" => labels, "datasets" => datasets}, version)
       when is_list(labels) and is_list(datasets) do
    with {:ok, dts} <- parse_labels(labels, version) do
      [first | _] = dts
      last = List.last(dts)

      topics =
        Enum.map(datasets, fn d ->
          top_words = Map.get(d, "topics", "")
          label = d |> Map.get("label", "") |> default_label(top_words)

          %{
            label: label,
            top_words: top_words,
            description: Map.get(d, "description", ""),
            values: build_values(dts, Map.get(d, "data", []))
          }
        end)

      {:ok,
       %{
         interval_start: DateTime.to_date(first),
         interval_end: DateTime.to_date(last),
         topics: topics
       }}
    end
  end

  defp parse_payload(other, _v), do: {:error, {:bad_payload, other}}

  defp build_values(dts, data) do
    Enum.zip(dts, data)
    |> Enum.map(fn {dt, v} ->
      %{"dt" => DateTime.to_iso8601(dt), "value" => to_number(v)}
    end)
  end

  defp to_number(n) when is_number(n), do: n
  defp to_number(_), do: 0

  defp default_label(label, top_words) when is_binary(label) do
    case String.trim(label) do
      "" -> top_words
      trimmed -> trimmed
    end
  end

  defp default_label(_, top_words), do: top_words

  defp parse_labels(labels, version) do
    labels
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {label, idx}, {:ok, acc} ->
      case parse_label(label, version, idx) do
        {:ok, dt} -> {:cont, {:ok, [dt | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, rev} -> {:ok, Enum.reverse(rev)}
      err -> err
    end
  end

  defp parse_label(<<d1, d2, ?., m1, m2, ?., y1, y2>>, _version, idx)
       when d1 in ?0..?9 and d2 in ?0..?9 and m1 in ?0..?9 and m2 in ?0..?9 and
              y1 in ?0..?9 and y2 in ?0..?9 do
    day = String.to_integer(<<d1, d2>>)
    month = String.to_integer(<<m1, m2>>)
    year = 2000 + String.to_integer(<<y1, y2>>)

    with {:ok, date} <- Date.new(year, month, day),
         {:ok, dt} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
      {:ok, DateTime.add(dt, idx, :second)}
    end
  end

  defp parse_label(label, version, _idx) when is_binary(label) do
    case Regex.named_captures(
           ~r/^(?<mon>[A-Z][a-z]{2}) (?<day>\d{1,2}), (?<h>\d{1,2}):(?<m>\d{2})$/,
           label
         ) do
      %{"mon" => mon, "day" => day, "h" => h, "m" => m} ->
        case Map.fetch(@year_overrides, version) do
          {:ok, year} ->
            with {:ok, month} <- month_from_abbr(mon),
                 {:ok, date} <- Date.new(year, month, String.to_integer(day)),
                 {:ok, time} <- Time.new(String.to_integer(h), String.to_integer(m), 0),
                 {:ok, dt} <- DateTime.new(date, time, "Etc/UTC") do
              {:ok, dt}
            end

          :error ->
            {:error, {:no_year_override, version, label}}
        end

      nil ->
        {:error, {:unrecognized_label, label}}
    end
  end

  defp month_from_abbr(abbr) do
    case Map.fetch(@month_map, abbr) do
      {:ok, m} -> {:ok, m}
      :error -> {:error, {:unknown_month, abbr}}
    end
  end
end
