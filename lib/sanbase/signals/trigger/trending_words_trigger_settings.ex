defmodule Sanbase.Signals.Trigger.TrendingWordsTriggerSettings do
  @derive [Jason.Encoder]
  @trigger_type "trending_words"
  @enforce_keys [:type, :channel, :trigger_time_iso_utc]

  defstruct type: @trigger_type,
            channel: nil,
            # ISO8601 string time in UTC
            trigger_time_iso_utc: nil,
            triggered?: false,
            payload: nil

  import Sanbase.Utils.Math, only: [to_integer: 1]
  alias __MODULE__

  def type(), do: @trigger_type

  defimpl Sanbase.Signals.Settings, for: TrendingWordsTriggerSettings do
    @trending_words_size 10
    @trending_words_hours [1, 8, 14]

    def triggered?(%TrendingWordsTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%TrendingWordsTriggerSettings{} = trigger) do
      IO.inspect(trigger)

      with true <- time_to_signal?(trigger),
           {:ok, payload} <- trigger_payload() do
        %TrendingWordsTriggerSettings{
          trigger
          | triggered?: true,
            payload: payload
        }
      else
        error ->
          %TrendingWordsTriggerSettings{trigger | triggered?: false}
      end
    end

    def cache_key(%TrendingWordsTriggerSettings{} = trigger) do
      data =
        [trigger.trigger_time_iso_utc]
        |> Jason.encode!()

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end

    defp time_to_signal?(%TrendingWordsTriggerSettings{trigger_time_iso_utc: trigger_time}) do
      case Time.from_iso8601(trigger_time) do
        {:ok, time} ->
          time.hour == Timex.now().hour

        _ ->
          false
      end
    end

    defp get_trending_word_query_params() do
      now = Timex.now()

      @trending_words_hours
      |> Enum.filter(&(&1 < now.hour))
      |> case do
        [] ->
          {
            Timex.beginning_of_day(Timex.shift(now, days: -1)),
            Timex.end_of_day(Timex.shift(now, days: -1)),
            @trending_words_hours |> Enum.max()
          }

        hours ->
          {
            Timex.beginning_of_day(now),
            Timex.end_of_day(now),
            hours |> Enum.max()
          }
      end
    end

    defp get_today_top_words() do
      {from, to, hour} = get_trending_word_query_params()

      Sanbase.SocialData.trending_words(
        :all,
        @trending_words_size,
        hour,
        from,
        to
      )
      |> case do
        {:ok, [%{top_words: top_words}]} ->
          {:ok, top_words}

        error ->
          :error
      end
    end

    defp get_max_len(top_words) do
      top_words
      |> Enum.map(fn tw -> String.length(tw.word) end)
      |> Enum.max()
    end

    defp trigger_payload() do
      get_today_top_words()
      |> IO.inspect()
      |> case do
        {:ok, top_words} ->
          max_len = get_max_len(top_words)
          {:ok, build_payload(top_words, max_len) |> IO.inspect()}

        _ ->
          :error
      end
    end

    defp build_payload(top_words, max_len) do
      top_words_strings =
        top_words
        |> Enum.sort_by(fn tw -> tw.score end, &>=/2)
        |> Enum.map(fn tw ->
          ~s(#{String.pad_trailing(tw.word, max_len)} | #{to_integer(tw.score)})
        end)

      top_words_table = Enum.join(top_words_strings, "\n")

      payload = """
      Trending words for: `#{Date.to_string(DateTime.to_date(Timex.now()))}`

      ```
      #{String.pad_trailing("Word", max_len)} | Score
      #{String.pad_trailing("-", max_len, "-")} | #{String.pad_trailing("-", max_len, "-")}
      #{top_words_table}
      ```
      More info: https://app.santiment.net/sonar
      """
    end
  end
end
