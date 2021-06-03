defmodule Sanbase.Alert.Trigger.TrendingWordsTriggerSettings do
  @moduledoc ~s"""
  Trigger settings for trending words alert.

  The alert supports the following operations:

  1. Send the list of trending words at predefined time every day
  2. Send an alert if some word enters the list of trending words.
  3. Send an alert if some project enters the list of trending words
  4. Send an alert if some project from a watchlist enters the list
     of trending words
  """
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.Math, only: [to_integer: 1]
  import Sanbase.Alert.Validation
  import Sanbase.Alert.Utils

  alias __MODULE__
  alias Sanbase.Alert.Type
  alias Sanbase.SocialData.TrendingWords

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "trending_words"
  @trending_words_size 10
  @enforce_keys [:type, :channel, :operation]

  defstruct type: @trigger_type,
            channel: nil,
            operation: %{},
            target: "default",
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{},
            extra_explanation: nil,
            template: nil

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          operation: Type.operation(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv(),
          extra_explanation: Type.extra_explanation()
        }

  # Validations
  validates(:operation, &valid_trending_words_operation?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:target, &valid_target?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  @spec get_data(%__MODULE__{}) :: TrendingWords.result()
  def get_data(%__MODULE__{}) do
    TrendingWords.get_currently_trending_words(@trending_words_size)
  end

  # private functions

  defimpl Sanbase.Alert.Settings, for: TrendingWordsTriggerSettings do
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
      now = Time.utc_now()
      after_15_mins = Time.add(now, 15 * 60, :second)

      case Sanbase.DateTimeUtils.time_in_range?(trigger_time, now, after_15_mins) do
        true ->
          template_kv = %{settings.target => template_kv(settings, top_words)}
          %TrendingWordsTriggerSettings{settings | triggered?: true, template_kv: template_kv}

        false ->
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
          template_kv = %{words => template_kv(settings, words)}
          %TrendingWordsTriggerSettings{settings | triggered?: true, template_kv: template_kv}
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
          template_kv =
            Enum.reduce(projects, %{}, fn project, acc ->
              case Project.is_trending?(project, trending_words_mapset) do
                true -> Map.put(acc, project.slug, template_kv(settings, project))
                false -> acc
              end
            end)

          %TrendingWordsTriggerSettings{
            settings
            | triggered?: template_kv != %{},
              template_kv: template_kv
          }
      end
    end

    defp template_kv(
           %{operation: %{send_at_predefined_time: true, trigger_time: trigger_time}} = settings,
           top_words
         ) do
      max_len = get_max_len(top_words)

      top_words_strings =
        top_words
        |> Enum.sort_by(fn tw -> tw.score end, &>=/2)
        |> Enum.map(fn tw ->
          ~s/#{String.pad_trailing(tw.word, max_len)} | #{to_integer(tw.score)}/
        end)

      trending_words_str = Enum.join(top_words_strings, "\n")

      # Having only the trigger_time won't be enough for the payload - include
      # also the date
      kv = %{
        type: TrendingWordsTriggerSettings.type(),
        datetime: "#{Date.utc_today()} #{trigger_time}",
        operation: settings,
        trending_words_list: top_words,
        trending_words_str: trending_words_str,
        sonar_url: SanbaseWeb.Endpoint.sonar_url(),
        extra_explanation: settings.extra_explanation
      }

      template =
        """
        🔔 Trending words at: {{datetime}}

        ```
        {{trending_words_str}}
        ```
        """
        |> maybe_extend_extra_explanation(settings.extra_explanation)

      {template, kv}
    end

    defp template_kv(%{operation: %{trending_word: true}} = settings, [word]) do
      kv = %{
        type: TrendingWordsTriggerSettings.type(),
        operation: settings,
        trending_words_list: [word],
        trending_words_str: "**#{word}**",
        trending_words_url: SanbaseWeb.Endpoint.trending_word_url(word),
        extra_explanation: settings.extra_explanation
      }

      template =
        """
        🔔 The word {{trending_words_str}} is in the trending words.
        """
        |> maybe_extend_extra_explanation(settings.extra_explanation)

      {template, kv}
    end

    defp template_kv(%{operation: %{trending_word: true}} = settings, [_, _ | _] = words) do
      {last, previous} = List.pop_at(words, -1)
      words_str = (Enum.map(previous, &"**#{&1}**") |> Enum.join(",")) <> " and **#{last}**"

      kv = %{
        type: TrendingWordsTriggerSettings.type(),
        operation: settings,
        trending_words_list: words,
        trending_words_str: words_str,
        trending_words_url: SanbaseWeb.Endpoint.trending_word_url(words),
        extra_explanation: settings.extra_explanation
      }

      template =
        """
        🔔 The words {{trending_words_str}} are in the trending words.
        """
        |> maybe_extend_extra_explanation(settings.extra_explanation)

      {template, kv}
    end

    defp template_kv(%{operation: %{trending_project: true}} = settings, project) do
      kv = %{
        type: TrendingWordsTriggerSettings.type(),
        operation: settings,
        project_name: project.name,
        project_ticker: project.ticker,
        project_slug: project.slug,
        extra_explanation: settings.extra_explanation
      }

      template =
        """
        🔔 \#{{project_ticker}} | **{{project_name}}** is in the trending words.
        """
        |> maybe_extend_extra_explanation(settings.extra_explanation)

      {template, kv}
    end

    defp get_max_len(top_words) do
      top_words
      |> Enum.map(&String.length(&1.word))
      |> Enum.max()
    end

    defp maybe_extend_extra_explanation(template, nil), do: template

    defp maybe_extend_extra_explanation(template, _extra_explanation) do
      template <> "{{extra_explanation}}\n"
    end
  end
end
