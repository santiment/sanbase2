defmodule Sanbase.SocialData.MetricAdapter do
  @moduledoc """
  Provides access and metadata for social metrics - these metrics are currently taken from internal service called metricshub.
  All `_total` metrics are served from 2 different places depending on the invocation.
  The ones with `slug` argument are served from clickhouse, the others with `text` argument
  from metricshub.
  """
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Metric.Transform
  import Sanbase.Utils.ErrorHandling, only: [not_implemented_function_for_metric_error: 2]

  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.Project

  @aggregations [:sum, :avg]
  @sources ["total"] ++ SocialHelper.sources()
  @social_volume_timeseries_metrics ["nft_social_volume"] ++
                                      Enum.map(@sources, fn source ->
                                        "social_volume_#{source}"
                                      end)

  @community_messages_count_timeseries_metrics [
    ## Community messages count counts the total amount of messages in a project's
    # own social medium. All messages are counted. Handles spam
    "community_messages_count_telegram",
    "community_messages_count_total"
  ]

  @social_dominance_timeseries_metrics ["social_dominance_ai_total"] ++
                                         Enum.map(@sources, fn source ->
                                           "social_dominance_#{source}"
                                         end)

  @sentiment_timeseries_metrics for name <- ["sentiment"],
                                    source <- @sources,
                                    type <- [
                                      "positive",
                                      "negative",
                                      "balance",
                                      "volume_consumed",
                                      "weighted"
                                    ],
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

  # plan related - the plan is upcase string
  @min_plan_map Enum.reduce(@metrics, %{}, fn metric, acc -> Map.put(acc, metric, "FREE") end)

  @access_map @metrics
              |> Enum.reduce(%{}, fn metric, acc ->
                Map.put(acc, metric, :restricted)
              end)

  @required_selectors Enum.into(@metrics, %{}, &{&1, []})
                      |> Map.put("social_active_users", [[:source]])

  @default_complexity_weight 1

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  defguard is_supported_nft_sv_selector(s)
           when is_map(s) and (is_map_key(s, :text) or is_map_key(s, :contract_address))

  @impl Sanbase.Metric.Behaviour
  def timeseries_data("nft_social_volume", selector, from, to, interval, _opts)
      when is_supported_nft_sv_selector(selector) do
    Sanbase.SocialData.social_volume(selector, from, to, interval, "total",
      metric: "nft_social_volume"
    )
    |> transform_to_value_pairs(:mentions_count)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data("nft_social_volume", selector, _from, _to, _interval, _opts)
      when not is_supported_nft_sv_selector(selector) do
    {:error,
     """
     The provided selector can't be used for metric: nft_social_volume.
     The supported selector fields for nft_social_volume are "text" and "contractAddress"
     """}
  end

  def timeseries_data(
        "nft_social_volume",
        %{contract_address: contract} = selector,
        from,
        to,
        interval,
        _opts
      )
      when is_binary(contract) do
    Sanbase.SocialData.social_volume(selector, from, to, interval, "total",
      metric: "nft_social_volume"
    )
    |> transform_to_value_pairs(:mentions_count)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, selector, from, to, interval, _opts)
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
  def timeseries_data_per_slug(metric, _from, _to, _operator, _threshold, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, selector, from, to, opts)
      when metric in @social_volume_timeseries_metrics or
             metric in @community_messages_count_timeseries_metrics do
    slug = Map.get(selector, :slug)

    case is_nil(slug) or is_binary(slug) do
      true ->
        case timeseries_data(metric, selector, from, to, "1h", opts) do
          {:ok, result} ->
            value = Enum.reduce(result, 0, &(&1.value + &2))
            {:ok, %{value: value}}

          {:error, error} ->
            {:error, error}
        end

      false ->
        {:error, "Aggregated timeseries data is not supported for lists of slugs."}
    end
  end

  def aggregated_timeseries_data(metric, selector, from, to, opts)
      when metric in @social_dominance_timeseries_metrics do
    slug = Map.get(selector, :slug)

    case is_nil(slug) or is_binary(slug) do
      true ->
        case timeseries_data(metric, selector, from, to, "1h", opts) do
          {:ok, result} ->
            value =
              Enum.map(result, & &1.value)
              |> Sanbase.Math.mean()

            {:ok, %{value: value}}

          {:error, error} ->
            {:error, error}
        end

      false ->
        {:error, "Aggregated timeseries data is not supported for lists of slugs."}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, _from, _to, _operator, _threshold, _opts) do
    not_implemented_function_for_metric_error("slugs_by_filter", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, _from, _to, _direction, _opts) do
    not_implemented_function_for_metric_error("metric", metric)
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
  def available_slugs(metric) do
    slugs =
      case metric do
        "social_volume_" <> _source ->
          Project.List.projects_slugs(preload?: false)

        "social_dominance_" <> _source ->
          Project.List.projects_slugs(preload?: false)

        "community_messages_count_" <> _source ->
          Project.List.projects_by_non_null_field(:telegram_link) |> Enum.map(& &1.slug)

        metric ->
          {:ok, %{available_selectors: selectors}} = metadata(metric)

          if :slug in selectors,
            do: raise("available_slugs/1 not implemented for #{metric}"),
            else: []
      end

    {:ok, slugs}
  end

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: @table_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(%{address: _address}), do: []

  def available_metrics(%{contract_address: contract_address}) do
    metrics = Sanbase.Metric.Utils.available_metrics_for_contract(__MODULE__, contract_address)

    # The metric is available only for `source`, not for `slug`
    metrics -- ["social_active_users"]
  end

  def available_metrics(%{slug: slug}) do
    with %Project{telegram_link: telegram_link} <- Project.by_slug(slug, preload?: false) do
      metrics =
        case is_binary(telegram_link) do
          true -> @metrics
          false -> @metrics -- @community_messages_count_timeseries_metrics
        end

      # These two metrics are not available for `slug` but for other selectors
      {:ok, metrics -- ["social_active_users", "nft_social_volume"]}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: []

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
        "nft_social_volume" -> [:contract_address]
        _ -> [:slug, :text, :founders]
      end

    min_interval =
      case metric do
        "social_active_users" -> "1d"
        _ -> "5m"
      end

    default_aggregation =
      cond do
        String.contains?(metric, "social_dominance") -> :avg
        String.contains?(metric, "volume_consumed") -> :avg
        true -> :sum
      end

    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: min_interval,
       default_aggregation: default_aggregation,
       available_aggregations: @aggregations,
       available_selectors: selectors,
       required_selectors: [],
       data_type: :timeseries,
       complexity_weight: @default_complexity_weight,
       hard_deprecate_after: nil,
       is_deprecated: false,
       is_timebound: false,
       docs: Enum.map(docs_links(metric), fn link -> %{link: link} end),
       is_label_fqn_metric: false
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime("nft_social_volume", _selector) do
    {:ok, ~U[2009-01-01 00:00:00Z]}
  end

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
  defp source_first_datetime("bitcointalk"), do: {:ok, ~U[2011-06-01 00:00:00Z]}
  defp source_first_datetime("youtube_videos"), do: {:ok, ~U[2018-02-13 00:00:00Z]}
  defp source_first_datetime("4chan"), do: {:ok, ~U[2018-02-13 00:00:00Z]}

  defp docs_links(metric) do
    list =
      cond do
        "nft_social_volume" == metric ->
          ["/metrics/nft-social-volume"]

        String.contains?(metric, ["sentiment_weighted", "sentiment_volume_consumed"]) ->
          ["/metrics/sentiment-metrics/weighted-sentiment-metrics"]

        String.contains?(metric, ["sentiment_positive", "sentiment_negative", "sentiment_balance"]) ->
          ["/metrics/sentiment-metrics/positive-negative-sentiment-metrics"]

        String.contains?(metric, "social_dominance") ->
          ["/metrics/social-dominance"]

        String.contains?(metric, "social_volume") ->
          ["/metrics/social-volume"]

        true ->
          []
      end

    Enum.map(list, &Path.join(["https://academy.santiment.net", &1]))
  end
end
