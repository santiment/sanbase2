defmodule Sanbase.Clickhouse.Github.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Metric.Transform
  import Sanbase.Metric.Utils
  import Sanbase.Utils.ErrorHandling, only: [not_implemented_function_for_metric_error: 2]

  alias Sanbase.Project
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
    "github_activity" => :total_github_activity,
    "dev_activity_contributors_count" => :total_dev_activity_contributors_count,
    "github_activity_contributors_count" => :total_github_activity_contributors_count
  }

  @timeseries_metrics Map.keys(@timeseries_metrics_function_mapping)
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics @metrics
  @restricted_metrics []

  @required_selectors Enum.into(@metrics, %{}, &{&1, []})
  @default_complexity_weight 0.3

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(metric, selector, from, to) do
    __MODULE__.BrokenData.get(metric, selector, from, to)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{organization: organization}, from, to, interval, opts) do
    timeseries_data(metric, %{organizations: [organization]}, from, to, interval, opts)
  end

  def timeseries_data(metric, %{organizations: organizations}, from, to, interval, _opts) do
    apply(
      Github,
      Map.get(@timeseries_metrics_function_mapping, metric),
      [organizations, from, to, interval, "None", nil]
    )
    |> transform_to_value_pairs()
  end

  def timeseries_data(metric, %{slug: slug_or_slugs}, from, to, interval, _opts) do
    case Project.List.github_organizations_by_slug(slug_or_slugs) do
      %{} = empty_map when map_size(empty_map) == 0 ->
        {:ok, []}

      %{} = organizations_map ->
        organizations = Map.values(organizations_map) |> List.flatten()

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
  def timeseries_data_per_slug(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, %{organization: organization}, from, to, opts) do
    aggregated_timeseries_data(metric, %{organizations: [organization]}, from, to, opts)
  end

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
    projects = Project.List.by_slugs(slugs, preload?: true, preload: [:github_organizations])

    org_to_slug_map = github_organization_to_slug_map(projects)
    organizations = github_organizatoins_of_projects(projects)

    case aggregated_timeseries_data(metric, %{organizations: organizations}, from, to, opts) do
      {:ok, map} ->
        result =
          Enum.reduce(map, %{}, fn {org, value}, acc ->
            slug = Map.get(org_to_slug_map, org)
            Map.update(acc, slug, value, &(&1 + value))
          end)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  defp github_organizatoins_of_projects(projects) do
    projects
    |> Enum.map(&Project.github_organizations/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
    |> List.flatten()
  end

  defp github_organization_to_slug_map(projects) do
    projects
    |> Enum.flat_map(fn project ->
      project.github_organizations
      |> Enum.map(fn org -> {String.downcase(org.organization), project.slug} end)
    end)
    |> Map.new()
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
  def first_datetime(_metric, %{organization: organization}) when is_binary(organization) do
    first_datetime_for_organizations([organization])
  end

  def first_datetime(_metric, %{slug: slug}) when is_binary(slug) do
    case Project.github_organizations(slug) do
      {:ok, organizations} when is_list(organizations) ->
        first_datetime_for_organizations(organizations)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, %{organization: organization})
      when is_binary(organization) do
    last_datetime_computed_at_for_organizations([organization])
  end

  def last_datetime_computed_at(_metric, %{slug: slug}) when is_binary(slug) do
    case Project.github_organizations(slug) do
      {:ok, organizations} when is_list(organizations) ->
        last_datetime_computed_at_for_organizations(organizations)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "5m",
       default_aggregation: :sum,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       required_selectors: @required_selectors[metric],
       data_type: :timeseries,
       is_timebound: false,
       complexity_weight: @default_complexity_weight,
       docs: Enum.map(docs_links(metric), fn l -> %{link: l} end),
       is_label_fqn_metric: false,
       is_deprecated: false,
       hard_deprecate_after: nil
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

  def docs_links(metric) do
    link = fn page -> "https://academy.santiment.net/metrics/development-activity/#{page}" end

    case metric do
      "dev_activity" -> [link.("development-activity")]
      "dev_activity_contributors_count" -> [link.("development-activity-contributors-count")]
      "github_activity" -> [link.("github-activity")]
      "github_activity_contributors_count" -> [link.("github-activity-contributors-count")]
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
  def available_metrics(%{address: _address}), do: []

  def available_metrics(%{contract_address: contract_address}) do
    available_metrics_for_contract(__MODULE__, contract_address)
  end

  def available_metrics(%{slug: slug}) when is_binary(slug) do
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
    cache_key = {__MODULE__, :slugs_with_github_org}

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      {:ok, Project.List.slugs_with_github_organization()}
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs(metric) when metric in @metrics do
    available_slugs()
  end

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: []

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  defp first_datetime_for_organizations([]), do: {:ok, nil}
  defp first_datetime_for_organizations(organizations), do: Github.first_datetime(organizations)

  defp last_datetime_computed_at_for_organizations([]), do: {:ok, nil}

  defp last_datetime_computed_at_for_organizations(organizations),
    do: Github.last_datetime_computed_at(organizations)
end
