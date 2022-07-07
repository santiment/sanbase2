defmodule Sanbase.Twitter.MetricAdapter do
  @behaviour Sanbase.Metric.Behaviour
  alias Sanbase.Model.Project

  @aggregations [:last]

  @timeseries_metrics ["twitter_followers"]
  @histogram_metrics []
  @table_metrics []

  @metrics @histogram_metrics ++ @timeseries_metrics ++ @table_metrics

  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, :free} end)

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
         {:ok, data} <- Sanbase.Twitter.twitter_timeseries_data(twitter_name, from, to, interval) do
      {:ok, data}
    else
      nil -> {:error, "Project with slug #{slug} does not exist"}
      error -> error
    end
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, selector, from, to, interval, opts \\ [])

  def timeseries_data_per_slug("twitter_followers", _selector, _from, _to, _interval, _opts) do
    {:error, "not_implemented"}
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data("twitter_followers", %{slug: _slug}, _from, _to, _opts) do
    {:error, "not_implemented"}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(_metric, _from, _to, _operator, _threshold, _opts) do
    {:error, "Slugs filtering is not implemented for twitter data."}
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(_metric, _from, _to, _direction, _opts) do
    {:error, "Slugs ordering is not implemented for twitter data."}
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
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "6h",
       default_aggregation: :last,
       available_aggregations: @aggregations,
       available_selectors: [:slug],
       data_type: :timeseries,
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
