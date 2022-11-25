defmodule Sanbase.Twitter.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Utils.ErrorHandling, only: [not_implemented_function_for_metric_error: 2]

  alias Sanbase.Project

  @aggregations [:last]

  @timeseries_metrics ["twitter_followers"]
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

  @free_metrics Enum.filter(@access_map, fn {_, level} -> level == :free end)
                |> Enum.map(&elem(&1, 0))

  @restricted_metrics Enum.filter(@access_map, fn {_, level} -> level == :restricted end)
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, []})

  @default_complexity_weight 1

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data("twitter_followers", %{slug: slug}, from, to, interval, _opts) do
    with %Project{} = project <- Project.by_slug(slug),
         {:ok, twitter_name} <- Project.twitter_handle(project),
         {:ok, data} <- Sanbase.Twitter.timeseries_data(twitter_name, from, to, interval) do
      {:ok, data}
    else
      nil -> {:error, "Project with slug #{slug} does not exist"}
      error -> error
    end
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_function_for_metric_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, _selector, _from, _to, _opts) do
    not_implemented_function_for_metric_error("aggregated_timeseries_data", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, _from, _to, _operator, _threshold, _opts) do
    not_implemented_function_for_metric_error("slugs_by_filter", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, _from, _to, _direction, _opts) do
    not_implemented_function_for_metric_error("slugs_order", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime("twitter_followers", %{slug: slug}) do
    with %Project{} = project <- Project.by_slug(slug),
         {:ok, twitter_name} <- Project.twitter_handle(project) do
      Sanbase.Twitter.first_datetime(twitter_name)
    end
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at("twitter_followers", %{slug: slug}) do
    with %Project{} = project <- Project.by_slug(slug),
         {:ok, twitter_name} <- Project.twitter_handle(project) do
      Sanbase.Twitter.last_datetime(twitter_name)
    end
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "6h",
       default_aggregation: :last,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       required_selectors: [:slug],
       data_type: :timeseries,
       is_timebound: false,
       complexity_weight: @default_complexity_weight
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "twitter_followers" -> {:ok, "Twitter Followers"}
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
    Sanbase.Metric.Utils.available_metrics_for_contract(__MODULE__, contract_address)
  end

  def available_metrics(%{slug: slug}) do
    with %Project{} = project <- Project.by_slug(slug) do
      case Project.twitter_handle(project) do
        {:ok, _} -> {:ok, @metrics}
        {:error, "Missing" <> _} -> {:ok, []}
        error -> error
      end
    end
  end

  @impl Sanbase.Metric.Behaviour
  def available_slugs() do
    cache_key = {__MODULE__, :slugs_with_twitter_handle} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      result =
        Project.List.projects()
        |> Enum.filter(fn project -> match?({:ok, _}, Project.twitter_handle(project)) end)
        |> Enum.map(& &1.slug)

      {:ok, result}
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
end
