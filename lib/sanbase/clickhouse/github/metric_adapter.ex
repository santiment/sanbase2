defmodule Sanbase.Clickhouse.Github.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Metric.Transform
  import Sanbase.Metric.Utils
  import Sanbase.Utils.ErrorHandling, only: [not_implemented_function_for_metric_error: 2]

  alias Sanbase.Project
  alias Sanbase.Clickhouse.Github

  @aggregations [:sum]

  # Version 2.0 of the activity metrics excludes the bots and caps the events of a
  # single contributor. See Sanbase.Clickhouse.Github.SqlQuery
  @available_versions %{
    "dev_activity" => ["1.0", "2.0"],
    "github_activity" => ["1.0", "2.0"],
    "dev_activity_contributors_count" => ["1.0"],
    "github_activity_contributors_count" => ["1.0"]
  }

  @timeseries_metrics Map.keys(@available_versions)
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

  def timeseries_data(metric, %{organizations: organizations}, from, to, interval, opts) do
    with {:ok, version} <- version(metric, opts) do
      github_timeseries_data(metric, organizations, from, to, interval, version)
      |> transform_to_value_pairs()
    end
  end

  def timeseries_data(metric, %{slug: slug_or_slugs}, from, to, interval, opts) do
    case Project.List.github_organizations_by_slug(slug_or_slugs) do
      %{} = organizations_map ->
        organizations = Map.values(organizations_map) |> List.flatten()
        timeseries_data(metric, %{organizations: organizations}, from, to, interval, opts)

      {:error, error} ->
        {:error, error}
    end
  end

  def timeseries_data(_metric, selector, _from, _to, _interval, _opts) when is_map(selector) do
    {:error,
     Sanbase.Metric.Utils.unsupported_selector_error(
       selector,
       "The selector must have at least one of the following fields: slug, organization, organizations"
     )}
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, %{organization: organization}, from, to, opts) do
    aggregated_timeseries_data(metric, %{organizations: [organization]}, from, to, opts)
  end

  def aggregated_timeseries_data(metric, %{organizations: organizations}, from, to, opts)
      when is_binary(organizations) or is_list(organizations) do
    with {:ok, version} <- version(metric, opts) do
      github_aggregated_timeseries_data(metric, List.wrap(organizations), from, to, version)
    end
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

  def aggregated_timeseries_data(_metric, selector, _from, _to, _opts)
      when is_map(selector) do
    {:error,
     Sanbase.Metric.Utils.unsupported_selector_error(
       selector,
       "The selector must have at least one of the following fields: slug, organization, organizations"
     )}
  end

  # The version is checked beforehand, so only the activity metrics get a version
  # other than 1.0
  defp github_timeseries_data(metric, organizations, from, to, interval, version) do
    case metric do
      "dev_activity" ->
        Github.dev_activity(organizations, from, to, interval, "None", nil, version: version)

      "github_activity" ->
        Github.github_activity(organizations, from, to, interval, "None", nil, version: version)

      "dev_activity_contributors_count" ->
        Github.dev_activity_contributors_count(organizations, from, to, interval, "None", nil)

      "github_activity_contributors_count" ->
        Github.github_activity_contributors_count(organizations, from, to, interval, "None", nil)
    end
  end

  defp github_aggregated_timeseries_data(metric, organizations, from, to, version) do
    case metric do
      "dev_activity" ->
        Github.total_dev_activity(organizations, from, to, version: version)

      "github_activity" ->
        Github.total_github_activity(organizations, from, to, version: version)

      "dev_activity_contributors_count" ->
        Github.total_dev_activity_contributors_count(organizations, from, to)

      "github_activity_contributors_count" ->
        Github.total_github_activity_contributors_count(organizations, from, to)
    end
  end

  defp version(metric, opts) do
    version = Keyword.get(opts, :version) || Sanbase.Metric.default_version()
    versions = Map.fetch!(@available_versions, metric)

    if version in versions do
      {:ok, version}
    else
      {:error,
       "Version #{version} is not available for the #{metric} metric. " <>
         "Available versions: #{Enum.join(versions, ", ")}"}
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
  def first_datetime(_metric, %{organization: organization}, _opts)
      when is_binary(organization) do
    first_datetime_for_organizations([organization])
  end

  def first_datetime(_metric, %{slug: slug}, _opts) when is_binary(slug) do
    case Project.github_organizations(slug) do
      {:ok, organizations} when is_list(organizations) ->
        first_datetime_for_organizations(organizations)

      {:error, error} ->
        {:error, error}
    end
  end

  def first_datetime(_metric, selector, _opts) when is_map(selector) do
    {:error,
     Sanbase.Metric.Utils.unsupported_selector_error(
       selector,
       "The selector must have at least one of the following fields: slug, organization, organizations"
     )}
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, %{organization: organization}, _opts)
      when is_binary(organization) do
    last_datetime_computed_at_for_organizations([organization])
  end

  def last_datetime_computed_at(_metric, %{slug: slug}, _opts) when is_binary(slug) do
    case Project.github_organizations(slug) do
      {:ok, organizations} when is_list(organizations) ->
        last_datetime_computed_at_for_organizations(organizations)

      {:error, error} ->
        {:error, error}
    end
  end

  def last_datetime_computed_at(_metric, selector, _opts) when is_map(selector) do
    {:error,
     Sanbase.Metric.Utils.unsupported_selector_error(
       selector,
       "The selector must have at least one of the following fields: slug, organization, organizations"
     )}
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "5m",
       stabilization_period: "4h",
       can_mutate: true,
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
       hard_deprecate_after: nil,
       status: "released"
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
  def available_versions(metric), do: {:ok, Map.fetch!(@available_versions, metric)}

  def available_versions(), do: {:ok, @available_versions}

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
  def available_metrics(%{address: _address}, _opts), do: {:ok, []}

  def available_metrics(%{contract_address: contract_address}, opts) do
    available_metrics_for_contract(__MODULE__, contract_address, opts)
  end

  def available_metrics(%{slug: slug}, _opts) when is_binary(slug) do
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
  def available_slugs(metric, _opts) when metric in @metrics do
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
