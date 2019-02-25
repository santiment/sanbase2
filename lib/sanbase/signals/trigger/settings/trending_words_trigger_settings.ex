defmodule Sanbase.Signals.Trigger.TrendingWordsTriggerSettings do
  @moduledoc ~s"""
  Trigger settings for daily trending words signal.
  The signal is sent at the configured `trigger_time` and sends the last set of
  trending words that was calculated.
  Currenly the trending words are calculated 3 times per day - at 01:00, 08:00
  and 14:00 UTC time
  """

  use Vex.Struct

  import Sanbase.Utils.Math, only: [to_integer: 1]
  import Sanbase.Signals.Utils
  import Sanbase.Signals.Validation

  alias __MODULE__
  alias Sanbase.Signals.Type

  @derive Jason.Encoder
  @trigger_type "trending_words"
  @trending_words_size 10
  @trending_words_hours [1, 8, 14]
  @minutes_needed_for_trending_words_calculation 15
  @enforce_keys [:type, :channel, :trigger_time]

  defstruct type: @trigger_type,
            channel: nil,
            trigger_time: nil,
            triggered?: false,
            payload: %{},
            target: "all",
            filtered_target_list: []

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          trigger_time: String.t(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  @type top_word_type :: %{
          word: String.t(),
          score: float()
        }

  # Validations
  validates(:channel, &valid_notification_channel/1)
  validates(:trigger_time, &valid_iso8601_datetime_string?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  @spec get_data(%TrendingWordsTriggerSettings{}) :: {:ok, list(top_word_type)} | :error
  def get_data(%TrendingWordsTriggerSettings{filtered_target_list: []}), do: :error

  def get_data(%TrendingWordsTriggerSettings{trigger_time: trigger_time}) do
    now = Timex.now()
    trigger_time = Time.from_iso8601!(trigger_time)
    now_time = DateTime.to_time(now)

    if Time.compare(now_time, trigger_time) in [:gt, :eq] do
      get_today_top_words(now)
    end
  end

  # private functions

  defp get_today_top_words(now) do
    {from, to, hour} = get_trending_word_query_params(now)

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

  defimpl Sanbase.Signals.Settings, for: TrendingWordsTriggerSettings do
    def triggered?(%TrendingWordsTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%TrendingWordsTriggerSettings{target: target} = settings) do
      case TrendingWordsTriggerSettings.get_data(settings) do
        {:ok, top_words} ->
          %TrendingWordsTriggerSettings{
            settings
            | triggered?: true,
              payload: %{target => payload(top_words)}
          }

        _ ->
          %TrendingWordsTriggerSettings{settings | triggered?: false}
      end
    end

    def cache_key(%TrendingWordsTriggerSettings{} = settings) do
      construct_cache_key([settings.trigger_time])
    end

    defp payload(top_words) do
      max_len = get_max_len(top_words)

      top_words_strings =
        top_words
        |> Enum.sort_by(fn tw -> tw.score end, &>=/2)
        |> Enum.map(fn tw ->
          ~s/#{String.pad_trailing(tw.word, max_len)} | #{to_integer(tw.score)}/
        end)

      top_words_table = Enum.join(top_words_strings, "\n")

      """
      Trending words for: `#{Date.to_string(DateTime.to_date(Timex.now()))}`

      ```
      #{String.pad_trailing("Word", max_len)} | Score
      #{String.pad_trailing("-", max_len, "-")} | #{String.pad_trailing("-", max_len, "-")}
      #{top_words_table}
      ```
      More info: #{SanbaseWeb.Endpoint.sonar_url()}
      """
    end

    defp get_max_len(top_words) do
      top_words
      |> Enum.max_by(fn %{word: word} -> String.length(word) end)
      |> Map.get(:word)
      |> String.length()
    end
  end
end
