defmodule Sanbase.SocialData.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Metric.Transform

  alias Sanbase.SocialData.SocialHelper
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
    "social_volume_twitter",
    "social_volume_bitcointalk",
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

  @sentiment_timeseries_metrics for name <- ["sentiment"],
                                    type <- ["positive", "negative", "balance", "volume_consumed"],
                                    source <-
                                      ["total"] ++ Sanbase.SocialData.SocialHelper.sources(),
                                    do: "#{name}_#{type}_#{source}"

  @active_users_timeseries_metrics ["social_active_users"]

  @timeseries_metrics @social_dominance_timeseries_metrics ++
                        @social_volume_timeseries_metrics ++
                        @community_messages_count_timeseries_metrics ++
                        @sentiment_timeseries_metrics ++
                        @active_users_timeseries_metrics

  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics
  @access_map Enum.reduce(@metrics, %{}, fn metric, acc -> Map.put(acc, metric, :restricted) end)
  @min_plan_map Enum.reduce(@metrics, %{}, fn metric, acc -> Map.put(acc, metric, :free) end)

  @default_complexity_weight 1

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{slug: _slug} = selector, from, to, interval, _opts)
      when metric in @social_volume_timeseries_metrics do
    "social_volume_" <> source = metric

    Sanbase.SocialData.social_volume(selector, from, to, interval, source)
    |> transform_to_value_pairs(:mentions_count)
  end

  def timeseries_data(metric, %{} = selector, from, to, interval, _opts)
      when metric in @social_dominance_timeseries_metrics do
    "social_dominance_" <> source = metric

    Sanbase.SocialData.social_dominance(selector, from, to, interval, source)
    |> transform_to_value_pairs(:dominance)
  end

  def timeseries_data(metric, %{slug: _slug} = selector, from, to, interval, _opts)
      when metric in @community_messages_count_timeseries_metrics do
    "community_messages_count_" <> source = metric

    Sanbase.SocialData.community_messages_count(selector, from, to, interval, source)
    |> transform_to_value_pairs(:mentions_count)
  end

  def timeseries_data(metric, %{text: _text} = selector, from, to, interval, _opts)
      when metric in @social_volume_timeseries_metrics do
    "social_volume_" <> source = metric

    Sanbase.SocialData.social_volume(selector, from, to, interval, source)
    |> transform_to_value_pairs(:mentions_count)
  end

  def timeseries_data(metric, %{} = selector, from, to, interval, _opts)
      when metric in @sentiment_timeseries_metrics do
    "sentiment_" <> type_source = metric
    {type, source} = SocialHelper.split_by_source(type_source)

    Sanbase.SocialData.sentiment(selector, from, to, interval, source, type)
    |> transform_to_value_pairs(:value)
  end

  def timeseries_data(metric, %{source: _source} = selector, from, to, interval, _opts)
      when metric in @active_users_timeseries_metrics do
    Sanbase.SocialData.social_active_users(selector, from, to, interval)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, selector, from, to, opts)
      when metric in @social_volume_timeseries_metrics or
             metric in @community_messages_count_timeseries_metrics do
    case timeseries_data(metric, selector, from, to, "1h", opts) do
      {:ok, result} ->
        {:ok, Enum.reduce(result, 0, &(&1.value + &2))}

      {:error, error} ->
        {:error, error}
    end
  end

  def aggregated_timeseries_data(metric, selector, from, to, opts)
      when metric in @social_dominance_timeseries_metrics do
    case timeseries_data(metric, selector, from, to, "1h", opts) do
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
  def slugs_by_filter(_metric, _from, _to, _operator, _threshold, _opts) do
    {:error, "Slugs filtering is not implemented for Social Data."}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(_metric, _from, _to, _direction, _opts) do
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
  def available_slugs(),
    do: {:ok, Project.List.projects_slugs(preload?: false)}

  @impl Sanbase.Metric.Behaviour
  def available_slugs("social_volume_" <> _source),
    do: {:ok, Project.List.projects_slugs(preload?: false)}

  def available_slugs("social_dominance_" <> _source),
    do: {:ok, Project.List.projects_slugs(preload?: false)}

  def available_slugs("community_messages_count_" <> _source),
    do: {:ok, Project.List.projects_by_non_null_field(:telegram_link) |> Enum.map(& &1.slug)}

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: @table_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(%{slug: slug}) do
    with %Project{telegram_link: telegram_link} <- Project.by_slug(slug, preload?: false) do
      metrics =
        case is_binary(telegram_link) do
          true -> @metrics
          false -> @metrics -- @community_messages_count_timeseries_metrics
        end

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
        "social_active_users" -> [:source]
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
  def first_datetime(metric, _selector) do
    {_metric, source} = SocialHelper.split_by_source(metric)
    source |> source_first_datetime()
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, _selector), do: {:ok, Timex.now()}

  # Private functions
  # total has the datetime of the earliest of all - bitcointalk
  defp source_first_datetime("total"), do: source_first_datetime("bitcointalk")
  defp source_first_datetime("telegram"), do: {:ok, ~U[2016-03-29 00:00:00Z]}
  defp source_first_datetime("twitter"), do: {:ok, ~U[2018-02-13 00:00:00Z]}
  defp source_first_datetime("reddit"), do: {:ok, ~U[2016-01-01 00:00:00Z]}
  defp source_first_datetime("discord"), do: {:ok, ~U[2016-05-21 00:00:00Z]}
  defp source_first_datetime("bitcointalk"), do: {:ok, ~U[2011-06-01 00:00:00Z]}
  defp source_first_datetime("professional_traders_chat"), do: {:ok, ~U[2018-02-09 00:00:00Z]}
end
