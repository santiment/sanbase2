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
  use Ecto.Schema

  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.ClickhouseRepo

  require Sanbase.Utils.Config, as: Config

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

  @default_sources [:telegram, :reddit]

  # When calculating the trending now words fetch the data for the last
  # N hours to ensure that there is some data and we're not in the middle
  # of computing the latest data
  @hours_back_ensure_has_data 3

  schema "trending_words_v4_top_500" do
    field(:dt, :utc_datetime)
    field(:word, :string)
    field(:volume, :float)
    field(:volume_normalized, :float)
    field(:unqiue_users, :integer)
    field(:score, :float)
    field(:source, :string)
    # ticker_slug
    field(:project, :string)
    field(:computed_at, :string)
  end

  @spec get_trending_words(
          DateTime.t(),
          DateTime.t(),
          interval,
          non_neg_integer,
          list(atom())
        ) ::
          {:ok, map()} | {:error, String.t()}
  def get_trending_words(from, to, interval, size, sources \\ @default_sources) do
    {query, args} = get_trending_words_query(from, to, interval, size, sources)

    ClickhouseRepo.query_reduce(query, args, %{}, fn
      [dt, word, _project, score], acc ->
        datetime = DateTime.from_unix!(dt)
        elem = %{word: word, score: score}
        Map.update(acc, datetime, [elem], fn words -> [elem | words] end)
    end)
  end

  @spec get_trending_projects(
          DateTime.t(),
          DateTime.t(),
          interval,
          non_neg_integer,
          list(atom())
        ) ::
          {:ok, map()} | {:error, String.t()}
  def get_trending_projects(from, to, interval, size, sources \\ @default_sources) do
    {query, args} = get_trending_words_query(from, to, interval, size, sources)

    ClickhouseRepo.query_reduce(query, args, %{}, fn
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
  @spec get_currently_trending_words(non_neg_integer(), list(atom())) ::
          {:ok, list(trending_word)} | {:error, String.t()}
  def get_currently_trending_words(size, sources \\ @default_sources)

  def get_currently_trending_words(size, sources) do
    now = Timex.now()
    from = Timex.shift(now, hours: -@hours_back_ensure_has_data)

    case get_trending_words(from, now, "1h", size, sources) do
      {:ok, %{} = empty_map} when map_size(empty_map) == 0 ->
        {:ok, []}

      {:ok, stats} ->
        {_, words} =
          stats
          |> Enum.max_by(fn {dt, _} -> DateTime.to_unix(dt) end)

        {:ok, words}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Get a list of the currently trending projects
  """
  @spec get_currently_trending_projects(non_neg_integer(), list(atom())) ::
          {:ok, list(trending_slug)} | {:error, String.t()}
  def get_currently_trending_projects(size, sources \\ @default_sources)

  def get_currently_trending_projects(size, sources) do
    now = Timex.now()
    from = Timex.shift(now, hours: -@hours_back_ensure_has_data)

    case get_trending_projects(from, now, "1h", size, sources) do
      {:ok, stats} ->
        {_, projects} =
          stats
          |> Enum.max_by(fn {dt, _} -> DateTime.to_unix(dt) end)

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
          list(atom())
        ) ::
          {:ok, list(word_stat)} | {:error, String.t()}
  def get_word_trending_history(word, from, to, interval, size, sources \\ @default_sources) do
    {query, args} = word_trending_history_query(word, from, to, interval, size, sources)

    ClickhouseRepo.query_transform(query, args, fn [dt, position] ->
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
          list(atom())
        ) ::
          {:ok, list(word_stat)} | {:error, String.t()}
  def get_project_trending_history(slug, from, to, interval, size, sources \\ @default_sources) do
    {query, args} = project_trending_history_query(slug, from, to, interval, size, sources)

    ClickhouseRepo.query_transform(query, args, fn [dt, position] ->
      position = if position > 0, do: position

      %{
        datetime: DateTime.from_unix!(dt),
        position: position
      }
    end)
    |> maybe_apply_function(fn result -> Enum.reject(result, &is_nil(&1.position)) end)
  end

  defp get_trending_words_query(from, to, interval, size, sources) do
    query = """
    SELECT
      t,
      word,
      any(project) AS project,
      SUM(score) / #{length(sources)} AS total_score
    FROM(
        SELECT
          toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
          word,
          any(project) AS project,
          argMax(score, dt) as score
        FROM #{Config.get(:trending_words_table)}
        PREWHERE
          dt >= toDateTime(?2) AND
          dt < toDateTime(?3) AND
          source IN (?4)
        GROUP BY t, word, source
        ORDER BY t, score DESC
    )
    GROUP BY t, word
    ORDER BY t, total_score DESC
    LIMIT ?5 BY t
    """

    sources = Enum.map(sources, &to_string/1)
    args = [str_to_sec(interval), from, to, sources, size]

    {query, args}
  end

  defp word_trending_history_query(word, from, to, interval, size, sources) do
    {query, args} = get_trending_words_query(from, to, interval, size, sources)
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

  defp project_trending_history_query(slug, from, to, interval, size, sources) do
    {query, args} = get_trending_words_query(from, to, interval, size, sources)
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

    ticker = Sanbase.Model.Project.ticker_by_slug(slug)

    args = args ++ [ticker <> "_" <> slug]
    {query, args}
  end
end
