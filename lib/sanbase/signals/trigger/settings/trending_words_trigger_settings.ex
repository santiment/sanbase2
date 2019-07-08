defmodule Sanbase.Signal.Trigger.TrendingWordsTriggerSettings do
  @moduledoc ~s"""
  Trigger settings for daily trending words signal.
  The signal is sent at the configured `trigger_time` and sends the last set of
  trending words that was calculated.
  Currenly the trending words are calculated 3 times per day - at 01:00, 08:00
  and 14:00 UTC time
  """

  use Vex.Struct

  import Sanbase.Math, only: [to_integer: 1]
  import Sanbase.Signal.Utils
  import Sanbase.Signal.Validation

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.SocialData.TrendingWords

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "trending_words"
  @trending_words_size 10
  @enforce_keys [:type, :channel, :operation]

  defstruct type: @trigger_type,
            channel: nil,
            triggered?: false,
            payload: %{},
            operation: %{},
            target: "default",
            filtered_target: %{list: []}

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          operation: Type.operation(),
          triggered?: boolean(),
          payload: Type.payload(),
          triggered?: boolean()
        }

  @type top_word_type :: %{
          word: String.t(),
          score: float()
        }

  # Validations
  validates(:channel, &valid_notification_channel/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  @spec get_data(%__MODULE__{}) :: {:ok, list(top_word_type)} | {:error, String.t()}
  def get_data(%__MODULE__{}) do
    TrendingWords.get_trending_now(@trending_words_size)
  end

  # private functions

  defimpl Sanbase.Signal.Settings, for: TrendingWordsTriggerSettings do
    def triggered?(%TrendingWordsTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%TrendingWordsTriggerSettings{filtered_target: %{list: []}} = settings, _trigger) do
      %TrendingWordsTriggerSettings{settings | triggered?: false}
    end

    def evaluate(%TrendingWordsTriggerSettings{} = settings, _trigger) do
      case TrendingWordsTriggerSettings.get_data(settings) do
        {:ok, top_words} when is_list(top_words) and top_words != [] ->
          build_result(top_words, settings)

        _ ->
          %TrendingWordsTriggerSettings{settings | triggered?: false}
      end
    end

    def cache_key(%TrendingWordsTriggerSettings{} = settings) do
      construct_cache_key([settings.operation, settings.target])
    end

    defp build_result(
           top_words,
           %{operation: %{send_at_predefined_time: true, trigger_time: trigger_time}} = settings
         ) do
      trigger_time = Sanbase.DateTimeUtils.time_from_iso8601!(trigger_time)

      if Time.compare(Time.utc_now(), trigger_time) == :gt do
        %TrendingWordsTriggerSettings{
          settings
          | triggered?: true,
            payload: %{settings.target => payload(settings, top_words)}
        }
      else
        %TrendingWordsTriggerSettings{settings | triggered?: false}
      end
    end

    defp payload(%{operation: %{send_at_predefined_time: true}}, top_words) do
      max_len = get_max_len(top_words)

      top_words_strings =
        top_words
        |> Enum.sort_by(fn tw -> tw.score end, &>=/2)
        |> Enum.map(fn tw ->
          ~s/#{String.pad_trailing(tw.word, max_len)} | #{to_integer(tw.score)}/
        end)

      top_words_table = Enum.join(top_words_strings, "\n")

      """
      Trending words at: `#{Timex.now() |> Timex.set(second: 0, microsecond: {0, 0})}`

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
