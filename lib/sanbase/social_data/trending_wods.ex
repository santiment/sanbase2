defmodule Sanbase.SocialData.TrendingWords do
  @trending_words_hours [1, 8, 14]
  @minutes_needed_for_trending_words_calculation 15

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
