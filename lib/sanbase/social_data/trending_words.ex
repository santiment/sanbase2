defmodule Sanbase.SocialData.TrendingWords do
  @moduledoc ~s"""
  Module for fetching the list of trending words

  This list does NOT calculate the most popular words on crypto social
  media overall - those would often be the same, redundant words
  such as ‘Bitcoin’, ‘Ethereum’, ‘crypto’ etc.

  Instead, our list aims to discover the biggest developing or emerging
  stories within the crypto community. That is why each day you’ll see
  a new batch of fresh topics, currently gaining steam on crypto social media.

  To do this, every 9 hours we calculate the top 10 words with the biggest
  spike in social media mentions compared to their average social volume
  in the previous 2 weeks.

  This signals an abnormally high interest in a previously uninspiring
  topic, making the list practical for discovering new and developing
  talking points in the crypto community.

  The results are sourced from more than 1000 crypto-specific social media
  channels, including hundreds of telegram groups, subredits, discord groups,
  bitcointalk forums, etc.
  """

  @trending_words_hours [1, 8, 14]
  @minutes_needed_for_trending_words_calculation 15

  @type trending_word :: %{
          word: String.t(),
          score: float()
        }

  @type result :: {:ok, list(trending_word)} | {:error, String.t()}

  @doc ~s"""
  Get a list of the currently trending words
  """
  @spec get_trending_now(non_neg_integer()) :: result
  def get_trending_now(size \\ 10)

  def get_trending_now(size) do
    now = Timex.now()

    {from, to, hour} = get_trending_word_query_params(now)

    Sanbase.SocialData.trending_words(:all, size, hour, from, to)
    |> case do
      {:ok, [%{top_words: top_words}]} ->
        {:ok, top_words}

      error ->
        {:error, error}
    end
  end

  defp get_trending_word_query_params(now) do
    @trending_words_hours
    |> Enum.map(fn hours ->
      now
      |> Timex.beginning_of_day()
      |> Timex.shift(hours: hours, minutes: @minutes_needed_for_trending_words_calculation)
    end)
    |> Enum.filter(&(&1 < now))
    |> case do
      # get last trending words from yesterday
      [] ->
        {
          Timex.beginning_of_day(Timex.shift(now, days: -1)),
          Timex.end_of_day(Timex.shift(now, days: -1)),
          @trending_words_hours |> Enum.max()
        }

      datetimes ->
        {
          Timex.beginning_of_day(now),
          Timex.end_of_day(now),
          datetimes |> Enum.map(& &1.hour) |> List.last()
        }
    end
  end
end
