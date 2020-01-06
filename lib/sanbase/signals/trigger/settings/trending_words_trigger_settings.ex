defmodule Sanbase.Signal.Trigger.TrendingWordsTriggerSettings do
  @moduledoc ~s"""
  Trigger settings for trending words signal.

  The signal supports the following operations:

  1. Send the list of trending words at predefined time every day
  2. Send a signal if some word enters the list of trending words.
  3. Send a signal if some project enters the list of trending words
  4. Send a signal if some project from a watchlist enters the list
     of trending words
  """

  use Vex.Struct

  import Sanbase.Math, only: [to_integer: 1]
  import Sanbase.Signal.Validation
  import Sanbase.Signal.Utils

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

  # Validations
  validates(:operation, &valid_trending_words_operation?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:target, &valid_target?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  @spec get_data(%__MODULE__{}) :: TrendingWords.result()
  def get_data(%__MODULE__{}) do
    TrendingWords.get_currently_trending_words(@trending_words_size)
  end

  # private functions

  defimpl Sanbase.Signal.Settings, for: TrendingWordsTriggerSettings do
    alias Sanbase.Model.Project

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

    defp build_result(
           top_words,
           %{operation: %{trending_word: true}, filtered_target: %{list: words}} = settings
         ) do
      top_words = top_words |> Enum.map(&String.downcase(&1.word))

      trending_words =
        MapSet.intersection(MapSet.new(top_words), MapSet.new(words))
        |> Enum.to_list()

      case trending_words do
        [] ->
          %TrendingWordsTriggerSettings{settings | triggered?: false}

        [_ | _] = words ->
          payload = %{words => payload(settings, words)}

          %TrendingWordsTriggerSettings{
            settings
            | triggered?: true,
              payload: payload
          }
      end
    end

    defp build_result(
           top_words,
           %{operation: %{trending_project: true}, filtered_target: %{list: slugs}} = settings
         ) do
      projects = Project.List.by_slugs(slugs)

      top_words =
        top_words
        |> Enum.map(&String.downcase(&1.word))

      project_words =
        Enum.flat_map(projects, &[&1.name, &1.ticker, &1.slug])
        |> MapSet.new()
        |> Enum.map(&String.downcase/1)

      trending_words_mapset =
        MapSet.intersection(MapSet.new(top_words), MapSet.new(project_words))

      case Enum.empty?(trending_words_mapset) do
        true ->
          # If there are no trending words in the intersection there is no
          # point of checking the projects separately
          %TrendingWordsTriggerSettings{settings | triggered?: false}

        false ->
          payload =
            Enum.reduce(projects, %{}, fn project, acc ->
              if Project.is_trending?(project, trending_words_mapset) do
                Map.put(acc, project.slug, payload(settings, project))
              else
                acc
              end
            end)

          %TrendingWordsTriggerSettings{settings | triggered?: true, payload: payload}
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

    defp payload(%{operation: %{trending_word: true}}, [word]) do
      """
      The word **#{word}** is in the trending words.

      More info here: #{SanbaseWeb.Endpoint.trending_word_url(word)}
      """
    end

    defp payload(%{operation: %{trending_word: true}}, [_, _ | _] = words) do
      {last, previous} = List.pop_at(words, -1)
      words_str = (Enum.map(previous, &"**#{&1}**") |> Enum.join(",")) <> " and **#{last}**"

      """
      The words #{words_str} are in the trending words.

      More info here: #{SanbaseWeb.Endpoint.trending_word_url(words)}
      """
    end

    defp payload(%{operation: %{trending_project: true}}, project) do
      """
      The project **#{project.name}** is in the trending words.

      More info here: #{Project.sanbase_link(project)}

      ![Volume and OHLC price chart for the past 90 days](#{chart_url(project, :volume)})
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
