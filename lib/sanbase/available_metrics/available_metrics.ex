defmodule Sanbase.AvailableMetrics do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  require Logger

  schema "available_metrics_data" do
    field(:metric, :string)
    field(:available_slugs, {:array, :string})

    timestamps()
  end

  @doc false
  def changeset(available_metrics, attrs) do
    available_metrics
    |> cast(attrs, [
      :metric,
      :available_slugs
    ])
    |> validate_required([:metric])
  end

  def get_not_updated_recently() do
    from(
      av in __MODULE__,
      where: av.updated_at < ^DateTime.add(DateTime.utc_now(), -2 * 86_400),
      order_by: [asc: av.updated_at],
      select: av.metric
    )
    |> Sanbase.Repo.all()
  end

  def get_all_updated() do
    from(
      av in __MODULE__,
      select: av.metric
    )
    |> Sanbase.Repo.all()
  end

  def update_metric(metric) do
    {:ok, slugs} = Sanbase.Metric.available_slugs(metric)
    {:ok, _} = create_or_update(%{metric: metric, available_slugs: slugs})
  rescue
    _ -> {:error, "Failed to update available slugs for #{metric}"}
  end

  def update_all() do
    metrics = Sanbase.Metric.available_metrics()

    metrics_not_updated_at_all = metrics -- get_all_updated()
    metrics_not_updated_recently = get_not_updated_recently()

    ordered_metrics = metrics_not_updated_at_all ++ metrics_not_updated_recently ++ metrics

    # Use the fact that Enum.uniq/1 keeps the order of the first occurence.
    # After the uniqueness is applied it is guaranteed that first we'll update the never updated metrics,
    # then those who were not updated recently, and then the rest
    ordered_metrics = Enum.uniq(ordered_metrics)

    for metric <- ordered_metrics do
      try do
        {:ok, slugs} = Sanbase.Metric.available_slugs(metric)
        {:ok, _} = create_or_update(%{metric: metric, available_slugs: slugs})
      rescue
        e ->
          Logger.error("Error updating available slugs for #{metric}: #{Exception.message(e)}")
      end
    end
  end

  def create_or_update(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert(
      conflict_target: :metric,
      on_conflict: {:replace, [:available_slugs, :updated_at]}
    )
  end

  def get_metrics_map() do
    metrics = Sanbase.Metric.available_metrics()
    metric_to_supported_assets_map = metric_to_available_slugs_maps()
    access_map = Sanbase.Metric.Helper.access_map()

    metrics
    |> Enum.map(fn metric ->
      {:ok, m} = Sanbase.Metric.metadata(metric)
      {:ok, available_selectors} = Sanbase.Metric.available_selectors(metric)

      %{
        metric: m.metric,
        internal_name: m.internal_metric,
        status: m.status,
        docs: Map.get(m, :docs) || [],
        available_assets: Map.get(metric_to_supported_assets_map, m.metric) || [],
        default_aggregation: m.default_aggregation,
        frequency: m.min_interval,
        frequency_seconds: Sanbase.DateTimeUtils.str_to_sec(m.min_interval),
        sanbase_access: "free",
        sanapi_access: "free",
        available_selectors: available_selectors,
        required_selectors: m.required_selectors,
        access: Map.get(access_map, metric)
      }
    end)
    |> Enum.sort_by(& &1.metric, :asc)
    |> Map.new(fn m -> {m.metric, m} end)
  end

  def get_metric_available_slugs(metric) do
    query = from(am in __MODULE__, where: am.metric == ^metric, select: am.available_slugs)

    case Sanbase.Repo.one(query) do
      nil -> {:error, "No record for available slugs for #{metric} found"}
      available_slugs -> {:ok, available_slugs}
    end
  end

  def apply_filters(metrics_map, filters) when is_map(metrics_map) do
    metrics_map
    |> Map.values()
    |> apply_filters(filters)
  end

  def apply_filters(metrics_list, filters) when is_list(metrics_list) do
    metrics_list
    |> maybe_apply_filter(:only_with_docs, filters)
    |> maybe_apply_filter(:only_intraday_metrics, filters)
    |> maybe_apply_filter(:match_metric_name, filters)
    |> maybe_apply_filter(:metric_supports_asset, filters)
    |> maybe_apply_filter(:only_asset_metrics, filters)
  end

  defp maybe_apply_filter(metrics, :only_with_docs, %{"only_with_docs" => "on"}) do
    metrics
    |> Enum.filter(&(&1.docs != []))
  end

  defp maybe_apply_filter(metrics, :only_intraday_metrics, %{"only_intraday_metrics" => "on"}) do
    metrics
    |> Enum.filter(&(&1.frequency_seconds < 86_400))
  end

  defp maybe_apply_filter(metrics, :match_metric_name, %{"match_metric_name" => query})
       when query != "" do
    query = String.downcase(query)

    metrics
    |> Enum.filter(
      &(String.contains?(&1.metric, query) or String.contains?(&1.internal_name, query))
    )
  end

  defp maybe_apply_filter(metrics, :metric_supports_asset, %{"metric_supports_asset" => str})
       when str != "" do
    metrics
    |> Enum.filter(&Enum.member?(&1.available_assets, str))
  end

  defp maybe_apply_filter(metrics, :only_asset_metrics, %{"only_asset_metrics" => "on"}) do
    metrics
    |> Enum.filter(&(&1.available_assets != [] and :slug in &1.available_selectors))
  end

  defp maybe_apply_filter(metrics, _, _), do: metrics

  defp metric_to_available_slugs_maps() do
    Sanbase.Repo.all(__MODULE__)
    |> Map.new(&{&1.metric, &1.available_slugs})
  end
end
