defmodule Sanbase.Clickhouse.Github.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  import Sanbase.Metric.Transform

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.Github

  @aggregations [:sum]

  @timeseries_metrics_function_mapping %{
    "dev_activity" => :dev_activity,
    "github_activity" => :github_activity,
    "dev_activity_contributors_count" => :dev_activity_contributors_count,
    "github_activity_contributors_count" => :github_activity_contributors_count
  }

  @aggregated_metrics_function_mapping %{
    "dev_activity" => :total_dev_activity,
    "github_activity" => :total_github_activity
  }

  @timeseries_metrics Map.keys(@timeseries_metrics_function_mapping)
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics @metrics
  @restricted_metrics []

  @default_complexity_weight 0.3

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{slug: slug}, from, to, interval, _opts) do
    case Project.github_organizations(slug) do
      {:ok, []} ->
        {:ok, []}

      {:ok, organizations} ->
        apply(
          Github,
          Map.get(@timeseries_metrics_function_mapping, metric),
          [organizations, from, to, interval, "None", nil]
        )
        |> transform_to_value_pairs()

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, %{organizations: organizations}, from, to, _opts)
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

  def aggregated_timeseries_data(metric, %{slug: slug_or_slugs}, from, to, opts) do
    slugs = slug_or_slugs |> List.wrap()

    organizations =
      slugs
      |> Project.List.by_slugs(preload?: true, preload: [:github_organizations])
      |> Enum.map(&Project.github_organizations/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> List.flatten()

    aggregated_timeseries_data(metric, %{organizations: organizations}, from, to, opts)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(_metric, _from, _to, _operator, _threshold, _opts) do
    {:error, "Slugs filtering is not implemented for github data. Use `dev_activity_1d` instead"}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(_metric, _from, _to, _direction, _opts) do
    {:error, "Slugs ordering is not implemented for github data. Use `dev_activity_1d` instead"}
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(_metric, %{slug: slug}) do
    case Project.github_organizations(slug) do
      {:ok, []} ->
        {:ok, nil}

      {:ok, [_ | _] = organizations} ->
        datetime =
          organizations
          |> Enum.map(fn org ->
            case Github.first_datetime(org) do
              {:ok, datetime} -> datetime
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.min_by(&DateTime.to_unix(&1))

        {:ok, datetime}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, %{slug: slug}) do
    case Project.github_organizations(slug) do
      {:ok, []} ->
        {:ok, nil}

      {:ok, [_ | _] = organizations} ->
        datetime =
          organizations
          |> Enum.map(fn org ->
            case Github.last_datetime_computed_at(org) do
              {:ok, datetime} -> datetime
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.max_by(&DateTime.to_unix(&1))

        {:ok, datetime}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       min_interval: "1m",
       default_aggregation: :sum,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       data_type: :timeseries,
       complexity_weight: @default_complexity_weight
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "dev_activity" ->
        {:ok, "Development Activity"}

      "github_activity" ->
        {:ok, "Github Activity"}

      "dev_activity_contributors_count" ->
        {:ok, "Number of Github contributors (related to dev activity events)"}

      "github_activity_contributors_count" ->
        {:ok, "Number of all Github contributors"}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

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
    case Project.github_organizations(slug) do
      {:ok, []} ->
        {:ok, []}

      {:ok, organizations} when is_list(organizations) ->
        {:ok, @metrics}

      {:error, error} ->
        {:error, error}
    end
  end

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
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map
end
