defmodule Sanbase.Clickhouse.Github.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  import Sanbase.Metric.Helper

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.Github

  @metrics_function_mapping %{
    "dev_activity" => :dev_activity,
    "github_activity" => :github_activity
  }

  @aggregated_metrics_function_mapping %{
    "dev_activity" => :total_dev_activity,
    "github_activity" => :total_github_activity
  }

  @metrics Map.keys(@metrics_function_mapping)

  @free_metrics @metrics
  @restricted_metrics []

  @impl Sanbase.Metric.Behaviour
  def get(metric, organizations, from, to, interval, opts) when metric in @metrics do
    apply(
      Github,
      Map.get(@metrics_function_mapping, metric),
      [
        organizations,
        from,
        to,
        interval,
        Keyword.get(opts, :transform, "None"),
        Keyword.get(opts, :ma_base)
      ]
    )
    |> transform_to_value_pairs(:activity)
  end

  @impl Sanbase.Metric.Behaviour
  def get_aggregated(metric, organizations, from, to, _opts) do
    apply(
      Github,
      Map.get(@aggregated_metrics_function_mapping, metric),
      [
        organizations,
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
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: {:ok, Project.List.project_slugs_with_organization()}

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics,
    do: {:ok, Project.List.project_slugs_with_organization()}

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
