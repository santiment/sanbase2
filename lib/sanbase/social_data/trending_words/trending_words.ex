defmodule Sanbase.SocialData.TrendingWords do
  @moduledoc ~s"""
  Module for fetching the list of trending words

  This list does NOT calculate the most popular words on crypto social
  media overall - those would often be the same, redundant words
  such as ‘Bitcoin’, ‘Ethereum’, ‘crypto’ etc.

  Instead, our list aims to discover the biggest developing or emerging
  stories within the crypto community. That is why each day you’ll see
  a new batch of fresh topics, currently gaining steam on crypto social media.

  This signals an abnormally high interest in a previously uninspiring
  topic, making the list practical for discovering new and developing
  talking points in the crypto community.

  The results are sourced from more than 1000 crypto-specific social media
  channels, including hundreds of telegram groups, subredits, discord groups,
  bitcointalk forums, etc.
  """

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @type word :: String.t()
  @type slug :: String.t()
  @type interval :: String.t()

  @typedoc """
  Defines the position in the list of trending words for a given datetime.
  If it has an integer value it means that the word was in the list of emergin
  words. If it has a nil value it means that the word was not in that list
  """
  @type position :: non_neg_integer() | nil

  @type trending_word :: %{
          word: word,
          score: float()
        }

  @type word_stat :: %{
          datetme: DateTime.t(),
          position: position
        }

  @spec get_trending_words(DateTime.t(), DateTime.t(), interval, non_neg_integer) ::
          {:ok, list(trending_word)} | {:error, String.t()}
  def get_trending_words(from, to, interval, size) do
    {query, args} = get_trending_words_query(from, to, interval, size)

    ClickhouseRepo.query_reduce(query, args, %{}, fn
      [dt, word, _project, score], acc ->
        datetime = DateTime.from_unix!(dt)
        elem = %{word: word, score: score}
        Map.update(acc, datetime, [elem], fn words -> [elem | words] end)
    end)
  end

  @doc ~s"""
  Get a list of the currently trending words
  """
  @spec get_trending_now(non_neg_integer()) :: {:ok, list(trending_word)} | {:error, String.t()}
  def get_trending_now(size \\ 10)

  def get_trending_now(size) do
    case get_trending_words(Timex.shift(Timex.now(), hours: -6), Timex.now(), "1h", size) do
      {:ok, stats} ->
        {_, words} =
          stats
          |> Enum.max_by(fn {dt, _} -> DateTime.to_unix(dt) end)

        {:ok, words}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec get_word_trending_history(word, DateTime.t(), DateTime.t(), interval, non_neg_integer) ::
          {:ok, list(word_stat)} | {:error, String.t()}
  def get_word_trending_history(word, from, to, interval, size) do
    {query, args} = word_trending_history_query(word, from, to, interval, size)

    ClickhouseRepo.query_transform(query, args, fn [dt, position] ->
      position = if position > 0, do: position

      %{
        datetime: DateTime.from_unix!(dt),
        position: position
      }
    end)
  end

  @spec get_project_trending_history(slug, DateTime.t(), DateTime.t(), interval, non_neg_integer) ::
          {:ok, list(word_stat)} | {:error, String.t()}
  def get_project_trending_history(slug, from, to, interval, size) do
    {query, args} = project_trending_history_query(slug, from, to, interval, size)

    ClickhouseRepo.query_transform(query, args, fn [dt, position] ->
      position = if position > 0, do: position

      %{
        datetime: DateTime.from_unix!(dt),
        position: position
      }
    end)
  end

  defp get_trending_words_query(from, to, interval, size) do
    query = """
    SELECT
      t,
      word,
      project,
      total_score AS score
    FROM(
        SELECT
           toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
           word,
           project,
           SUM(score) / 4 AS total_score
        FROM trending_words
        PREWHERE
          dt >= toDateTime(?2) AND
          dt < toDateTime(?3) AND
          source NOT IN ('twitter', 'bitcointalk') AND
          dt = t
        GROUP BY t, word, project
        ORDER BY total_score DESC
        LIMIT ?4 BY t
    )
    ORDER BY t, score
    """

    args = [str_to_sec(interval), from, to, size]

    {query, args}
  end

  defp word_trending_history_query(word, from, to, interval, size) do
    {query, args} = get_trending_words_query(from, to, interval, size)
    args_len = length(args)
    next_pos = args_len + 1

    query =
      [
        """
        SELECT
          t,
          toUInt32(indexOf(groupArray(?#{args_len})(word), ?#{next_pos}))
        FROM(
        """,
        query,
        """
        )
        GROUP BY t
        ORDER BY t
        """
      ]
      |> to_string()

    args = args ++ [word]
    {query, args}
  end

  defp project_trending_history_query(slug, from, to, interval, size) do
    IO.inspect(
      label:
        "message; #{
          String.replace_leading("#{__ENV__.file}", "#{File.cwd!()}", "") |> Path.relative()
        }:#{__ENV__.line()}"
    )

    {query, args} = get_trending_words_query(from, to, interval, size)
    args_len = length(args)
    next_pos = args_len + 1

    query =
      [
        """
        SELECT
          t,
          toUInt32(indexOf(groupArray(?#{args_len})(project), ?#{next_pos}))
        FROM(
        """,
        query,
        """
        )
        GROUP BY t
        ORDER BY t
        """
      ]
      |> to_string()

    ticker =
      Sanbase.Model.Project.ticker_by_slug(slug) |> IO.inspect(label: "195", limit: :infinity)

    args = args ++ [ticker <> "_" <> slug]
    {query, args}
  end
end
