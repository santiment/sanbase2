defmodule Sanbase.SocialData.TrendingWords do
  @moduledoc ~s"""
  Module for fetching the list of trending words

  This list does NOT calculate the most popular words on crypto social
  media overall - those would often be the same, redundant words
  such as ‘Bitcoin’, ‘Ethereum’, ‘crypto’ etc.

  Instead, our list aims to discover the biggest developing or emerging
  stories within the crypto community. That is why each day you’ll see
  a new batch of fresh topics, currently gaining steam on crypto social media.

  This shows an abnormally high interest in a previously uninspiring
  topic, making the list practical for discovering new and developing
  talking points in the crypto community.

  The results are sourced from more than 1000 crypto-specific social media
  channels, including hundreds of telegram groups, subredits, discord groups,
  bitcointalk forums, etc.
  """

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]
  import Sanbase.Metric.SqlQuery.Helper, only: [to_unix_timestamp: 3, dt_to_unix: 2]

  alias Sanbase.ClickhouseRepo

  @type word :: String.t()
  @type slug :: String.t()
  @type interval :: String.t()

  @typedoc """
  Defines the position in the list of trending words for a given datetime.
  If it has an integer value it means that the word was in the list of emerging
  words. If it has a nil value it means that the word was not in that list
  """
  @type position :: non_neg_integer() | nil

  @type trending_word :: %{
          word: word,
          score: float()
        }

  @type trending_slug :: %{
          slug: slug,
          score: float()
        }

  @type word_stat :: %{
          datetme: DateTime.t(),
          position: position
        }
  @table "trending_words_docs_v4"

  # When calculating the trending now words fetch the data for the last
  # N hours to ensure that there is some data and we're not in the middle
  # of computing the latest data
  @hours_back_ensure_has_data 3

  @spec get_trending_words(
          DateTime.t(),
          DateTime.t(),
          interval,
          non_neg_integer,
          atom(),
          atom()
        ) ::
          {:ok, map()} | {:error, String.t()}
  def get_trending_words(from, to, interval, size, source, word_type_filter \\ :all) do
    source = if source == :all, do: default_source(), else: to_string(source)

    query_struct = get_trending_words_query(from, to, interval, size, source, word_type_filter)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn
      [
        dt,
        word,
        project,
        score,
        context,
        summary,
        bullish_summary,
        bearish_summary,
        sentiment_ratios,
        bb_sentiment_ratios
      ],
      acc ->
        slug = if project, do: String.split(project, "_", parts: 2) |> List.last()
        datetime = DateTime.from_unix!(dt)
        # The percentage of the documents that mention the word that have
        # postive, negative or netural sentiment. The values are in the range [0, 1]
        # and add up to 1
        [positive_sentiment, neutral_sentiment, negative_sentiment] = sentiment_ratios
        [positive_bb_sentiment, neutral_bb_sentiment, negative_bb_sentiment] = bb_sentiment_ratios

        summaries = [%{source: source, datetime: datetime, summary: summary}]
        context = transform_context(context)

        elem = %{
          word: word,
          slug: slug,
          score: score,
          context: context,
          # Keep both summaries and summary for backwards compatibility. Remove summaries later
          summary: summary,
          bullish_summary: bullish_summary,
          bearish_summary: bearish_summary,
          summaries: summaries,
          positive_sentiment_ratio: positive_sentiment,
          negative_sentiment_ratio: negative_sentiment,
          neutral_sentiment_ratio: neutral_sentiment,
          positive_bb_sentiment_ratio: positive_bb_sentiment,
          negative_bb_sentiment_ratio: negative_bb_sentiment,
          neutral_bb_sentiment_ratio: neutral_bb_sentiment
        }

        Map.update(acc, datetime, [elem], fn words -> [elem | words] end)
    end)
  end

  defp transform_context(context) do
    context
    |> Enum.map(fn c ->
      %{"word" => word, "score" => score} =
        c
        |> String.replace("'", ~s|\"|)
        |> Jason.decode!()

      %{word: word, score: score}
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(10)
  end

  @spec get_trending_projects(
          DateTime.t(),
          DateTime.t(),
          interval,
          non_neg_integer,
          atom()
        ) ::
          {:ok, map()} | {:error, String.t()}
  def get_trending_projects(from, to, interval, size, source) do
    source = if source == :all, do: default_source(), else: to_string(source)
    # The word_type_filter is :all for backwards compatibility. The logic is
    # to find if any of the top `size` trending words are projects, not just
    # taking the top 10 projects, regardless of their position in the overall
    # ranking
    query_struct = get_trending_words_query(from, to, interval, size, source, :all)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn
      [_dt, _word, nil, _score], acc ->
        acc

      [dt, _word, project, score], acc ->
        datetime = DateTime.from_unix!(dt)
        [_ticker, slug] = String.split(project, "_")
        elem = %{slug: slug, score: score}
        Map.update(acc, datetime, [elem], fn slugs -> [elem | slugs] end)
    end)
  end

  @doc ~s"""
  Get a list of the currently trending words
  """
  @spec get_currently_trending_words(non_neg_integer(), atom()) ::
          {:ok, list(trending_word)} | {:error, String.t()}
  def get_currently_trending_words(size, source) do
    source = if source == :all, do: default_source(), else: to_string(source)
    now = Timex.now()
    from = Timex.shift(now, hours: -@hours_back_ensure_has_data)

    case get_trending_words(from, now, "1h", size, source) do
      {:ok, %{} = empty_map} when map_size(empty_map) == 0 ->
        {:ok, []}

      {:ok, stats} ->
        {_, words} = stats |> Enum.max_by(fn {dt, _} -> DateTime.to_unix(dt) end)
        {:ok, words}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Get a list of the currently trending projects
  """
  @spec get_currently_trending_projects(non_neg_integer(), atom()) ::
          {:ok, list(trending_slug)} | {:error, String.t()}
  def get_currently_trending_projects(size, source) do
    source = if source == :all, do: default_source(), else: to_string(source)
    now = Timex.now()
    from = Timex.shift(now, hours: -@hours_back_ensure_has_data)

    case get_trending_projects(from, now, "1h", size, source) do
      {:ok, stats} ->
        {_, projects} = stats |> Enum.max_by(fn {dt, _} -> DateTime.to_unix(dt) end)
        {:ok, projects}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec get_word_trending_history(
          word,
          DateTime.t(),
          DateTime.t(),
          interval,
          non_neg_integer,
          atom()
        ) ::
          {:ok, list(word_stat)} | {:error, String.t()}
  def get_word_trending_history(word, from, to, interval, size, source) do
    source = if source == :all, do: default_source(), else: to_string(source)
    query_struct = word_trending_history_query(word, from, to, interval, size, source)

    ClickhouseRepo.query_transform(query_struct, fn [dt, position] ->
      position = if position > 0, do: position

      %{
        datetime: DateTime.from_unix!(dt),
        position: position
      }
    end)
    |> maybe_apply_function(fn result -> Enum.reject(result, &is_nil(&1.position)) end)
  end

  @spec get_project_trending_history(
          slug,
          DateTime.t(),
          DateTime.t(),
          interval,
          non_neg_integer,
          atom()
        ) ::
          {:ok, list(word_stat)} | {:error, String.t()}
  def get_project_trending_history(slug, from, to, interval, size, source) do
    source = if source == :all, do: default_source(), else: to_string(source)
    query_struct = project_trending_history_query(slug, from, to, interval, size, source)

    ClickhouseRepo.query_transform(query_struct, fn [dt, position] ->
      position = if position > 0, do: position

      %{
        datetime: DateTime.from_unix!(dt),
        position: position
      }
    end)
    |> maybe_apply_function(fn result -> Enum.reject(result, &is_nil(&1.position)) end)
  end

  # Private functions

  defp get_trending_words_query(from, to, interval, size, source, word_type_filter) do
    sql = """
    SELECT
      t,
      word,
      project AS project2,
      score,
      context,
      summary,
      bullish_summary,
      bearish_summary,
      sentiment_ratios,
      bb_sentiment_ratios
    FROM
    (
        SELECT
            #{to_unix_timestamp(interval, "dt", argument_name: "interval")} AS t,
            dt,
            max(dt) OVER (PARTITION BY t) AS last_dt_in_group,
            argMax(word, computed_at) AS word,
            argMax(project, computed_at) AS project,
            argMax(score, computed_at) / {{score_equalizer}} AS score,
            argMax(words_context, computed_at) AS context,
            argMax(summary, computed_at) AS summary,
            argMax(bullish_summary, computed_at) AS bullish_summary,
            argMax(bearish_summary, computed_at) AS bearish_summary,
            (argMax(positive_ratio, computed_at), argMax(neutral_ratio, computed_at), argMax(negative_ratio, computed_at)) AS sentiment_ratios,
            (argMax(positive_bb_ratio, computed_at), argMax(neutral_bb_ratio, computed_at), argMax(negative_bb_ratio, computed_at)) AS bb_sentiment_ratios
        FROM #{@table}
        WHERE (dt >= toDateTime({{from}})) AND (dt < toDateTime({{to}})) AND (source = {{source}})
        GROUP BY
            t,
            dt,
            source,
            docs_id
        #{word_type_filter_str(word_type_filter)}
    )
    WHERE (dt = last_dt_in_group) AND (dt = t)
    ORDER BY
        t ASC,
        score DESC
    LIMIT {{limit}} BY t
    """

    params = %{
      interval: str_to_sec(interval),
      from: dt_to_unix(:from, from),
      to: dt_to_unix(:to, to),
      source: source,
      limit: size,
      # The score equalizer is used to make sure that the score is comparable in absolute values
      # no matter if the source is `reddit`, `4chat,reddit` or `reddit,telegram,twitter_crypto`
      score_equalizer: length(String.split(source, ","))
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp word_type_filter_str(word_type_filter) do
    case word_type_filter do
      :all -> ""
      :project -> "HAVING project IS NOT NULL"
      :non_project -> "HAVING project IS NULL"
    end
  end

  defp word_trending_history_query(word, from, to, interval, size, source) do
    query_struct = get_trending_words_query(from, to, interval, size, source, :all)

    sql =
      [
        """
        SELECT
          t,
          toUInt32(indexOf(groupArray({{limit}})(word), {{word}}))
        FROM(
        """,
        query_struct.sql,
        """
        )
        GROUP BY t
        ORDER BY t
        """
      ]
      |> to_string()

    query_struct
    |> Sanbase.Clickhouse.Query.put_sql(sql)
    |> Sanbase.Clickhouse.Query.add_parameter(:word, word)
  end

  defp project_trending_history_query(slug, from, to, interval, size, source) do
    query_struct = get_trending_words_query(from, to, interval, size, source, :all)

    sql = """
    SELECT
      t,
      toUInt32(indexOf(groupArray({{limit}})(project2), {{ticker_slug}})) AS pos_in_top_n
    FROM ( #{query_struct.sql} )
    GROUP BY t
    ORDER BY t
    """

    ticker_slug = Sanbase.Project.ticker_by_slug(slug) <> "_" <> slug

    query_struct
    |> Sanbase.Clickhouse.Query.put_sql(sql)
    |> Sanbase.Clickhouse.Query.add_parameter(:ticker_slug, ticker_slug)
  end

  defp default_source do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "prod" -> "reddit,telegram,twitter_crypto"
      _ -> "4chan,reddit,telegram"
    end
  end
end
