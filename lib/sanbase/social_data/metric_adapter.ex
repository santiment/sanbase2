defmodule Sanbase.SocialData.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Metric.Helper

  alias Sanbase.Model.Project

  @aggregations [:sum]

  @social_volume_timeseries_metrics [
    # Social volume counts the mentions of a given word or words describing as subject
    # A project can be addressed by different words.
    # Example: `btc` and `bitcoin` refer to bitcoin
    "social_volume_telegram",
    "social_volume_discord",
    "social_volume_reddit",
    "social_volume_professional_traders_chat",
    "social_volume_total"
  ]

  @community_messages_count_timeseries_metrics [
    ## Community messages count counts the total amount of messages in a project's
    # own social medium. All messages are counted. Handles spam
    "community_messages_count_telegram",
    "community_messages_count_total"
  ]

  @social_dominance_timeseries_metrics [
    "social_dominance_telegram",
    "social_dominance_discord",
    "social_dominance_reddit",
    "social_dominance_professional_traders_chat",
    "social_dominance_total"
  ]

  @timeseries_metrics @social_dominance_timeseries_metrics ++
                        @social_volume_timeseries_metrics ++
                        @community_messages_count_timeseries_metrics

  @histogram_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics
  @access_map Enum.reduce(@metrics, %{}, fn metric, acc -> Map.put(acc, metric, :restricted) end)
  @min_plan_map Enum.reduce(@metrics, %{}, fn metric, acc -> Map.put(acc, metric, :free) end)

  @default_complexity_weight 1

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{slug: slug} = selector, from, to, interval, _aggregation)
      when metric in @social_volume_timeseries_metrics do
    "social_volume_" <> source = metric

    Sanbase.SocialData.social_volume(selector, from, to, interval, source)
    |> transform_to_value_pairs(:mentions_count)
  end

  def timeseries_data(metric, %{} = selector, from, to, interval, _aggregation)
      when metric in @social_dominance_timeseries_metrics do
    "social_dominance_" <> source = metric

    Sanbase.SocialData.social_dominance(selector, from, to, interval, source)
    |> transform_to_value_pairs(:dominance)
  end

  def timeseries_data(metric, %{slug: slug}, from, to, interval, _aggregation)
      when metric in @community_messages_count_timeseries_metrics do
    "community_messages_count_" <> source = metric

    Sanbase.SocialData.community_messages_count(slug, from, to, interval, source)
    |> transform_to_value_pairs(:mentions_count)
  end

  def timeseries_data(metric, %{text: text} = selector, from, to, interval, _aggregation)
      when metric in @social_volume_timeseries_metrics do
    "social_volume_" <> source = metric

    Sanbase.SocialData.topic_search(text, from, to, interval, source)
    |> transform_to_value_pairs(:mentions_count)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, selector, from, to, aggregation)
      when metric in @social_volume_timeseries_metrics or
             metric in @community_messages_count_timeseries_metrics do
    case timeseries_data(metric, selector, from, to, "1h", aggregation) do
      {:ok, result} ->
        {:ok, Enum.reduce(result, 0, &(&1.value + &2))}

      {:error, error} ->
        {:error, error}
    end
  end

  def aggregated_timeseries_data(metric, selector, from, to, aggregation)
      when metric in @social_dominance_timeseries_metrics do
    case timeseries_data(metric, selector, from, to, "1h", aggregation) do
      {:ok, result} ->
        result =
          Enum.reduce(result, 0, &(&1.value + &2))
          |> Sanbase.Math.average()

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(_metric, _from, _to, _operator, _threshold, _aggregation) do
    {:error, "Slugs filtering is not implemented for Social Data."}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(_metric, _from, _to, _direction, _aggregation) do
    {:error, "Slugs ordering is not implemented for Social Data."}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) when metric in @metrics do
    human_readable_name =
      String.split(metric, "_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    {:ok, human_readable_name}
  end

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    # Providing a 2 element tuple `{any, integer}` will use that second element
    # as TTL for the cache key
    Sanbase.Cache.get_or_store({:social_metrics_available_slugs, 1800}, fn ->
      Sanbase.SocialData.SocialVolume.social_volume_projects()
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(_metric), do: available_slugs()

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(%{slug: slug}) do
    with %Project{telegram_link: telegram_link} <- Project.by_slug(slug, preload?: false),
         {:ok, slugs} <- available_slugs() do
      metrics = if slug in slugs, do: @metrics, else: []

      # Add or remove community messages metrics based on the presence of telegram link
      # If community messages count metric is added twice, that would be comensated
      # by the uniq()
      metrics =
        if is_binary(telegram_link),
          do: (metrics ++ @community_messages_count_timeseries_metrics) |> Enum.uniq(),
          else: metrics -- @community_messages_count_timeseries_metrics

      {:ok, metrics}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: []

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    selectors =
      case metric do
        "community_messages_count" <> _ -> [:slug]
        _ -> [:slug, :text]
      end

    {:ok,
     %{
       metric: metric,
       min_interval: "5m",
       default_aggregation: :sum,
       available_aggregations: @aggregations,
       available_selectors: selectors,
       data_type: :timeseries,
       complexity_weight: @default_complexity_weight
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, _selector), do: metric |> metric_to_source |> source_first_datetime()

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, _selector), do: {:ok, Timex.now()}

  # Private functions

  # total has the datetime of the earliest of all - bitcointalk
  defp source_first_datetime("total"), do: {:ok, ~U[2016-01-01 00:00:00Z]}
  defp source_first_datetime("telegram"), do: {:ok, ~U[2016-03-29 00:00:00Z]}
  defp source_first_datetime("twitter"), do: {:ok, ~U[2018-02-13 00:00:00Z]}
  defp source_first_datetime("reddit"), do: {:ok, ~U[2016-01-01 00:00:00Z]}
  defp source_first_datetime("discord"), do: {:ok, ~U[2016-05-21 00:00:00Z]}
  defp source_first_datetime("professional_traders_chat"), do: {:ok, ~U[2018-02-09 00:00:00Z]}

  defp metric_to_source("social_volume_" <> source), do: source
  defp metric_to_source("social_dominance_" <> source), do: source
  defp metric_to_source("community_messages_count_" <> source), do: source
end
