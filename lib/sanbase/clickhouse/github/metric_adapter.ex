defmodule Sanbase.Clickhouse.Github.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  import Sanbase.Metric.Helper

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.Github

  @timeseries_metrics_function_mapping %{
    "dev_activity" => :dev_activity,
    "github_activity" => :github_activity
  }

  @aggregated_metrics_function_mapping %{
    "dev_activity" => :total_dev_activity,
    "github_activity" => :total_github_activity
  }

  @timeseries_metrics Map.keys(@timeseries_metrics_function_mapping)
  @histogram_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics

  @free_metrics @metrics
  @restricted_metrics []

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, slug, from, to, interval, _aggregation)
      when metric in @metrics do
    case Project.github_organizations(slug) do
      {:ok, organizations} ->
        apply(
          Github,
          Map.get(@timeseries_metrics_function_mapping, metric),
          [
            organizations,
            from,
            to,
            interval,
            "None",
            nil
          ]
        )
        |> transform_to_value_pairs(:activity)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, organizations, from, to, _aggregation)
      when is_binary(organizations) or is_list(organizations) do
    apply(
      Github,
      Map.get(@aggregated_metrics_function_mapping, metric),
      [
        List.wrap(organizations),
        from,
        to
      ]
    )
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(metric, slug) when metric in @metrics do
    Github.first_datetime(slug)
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) when metric in @metrics do
    {:ok,
     %{
       metric: metric,
       min_interval: "1m",
       default_aggregation: :sum,
       available_aggregations: [:sum]
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) when metric in @metrics do
    case metric do
      "dev_activity" -> {:ok, "Development Activity"}
      "github_activity" -> {:ok, "Github Activity"}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: [:sum]

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    # Providing a 2 element tuple `{any, integer}` will use that second element
    # as TTL for the cache key
    Sanbase.Cache.get_or_store({:slugs_with_github_org, 1800}, fn ->
      {:ok, Project.List.project_slugs_with_organization()}
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map() do
    %{
      "dev_activity" => :free,
      "github_activity" => :free
    }
  end
end
