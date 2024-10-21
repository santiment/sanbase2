defmodule Sanbase.Clickhouse.Metric.Registry do
  require Logger

  @sleep_time %{
    1 => 0,
    2 => 5,
    3 => 10,
    4 => 20,
    5 => 100,
    6 => 500,
    7 => 2000,
    8 => 2000,
    9 => 3000,
    10 => 5000
  }
  @max_attempts 10

  # The metrics registry is a singleton that holds all the metrics that are
  def get_metrics_from_registry() do
    key = {__MODULE__, :get_metrics} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(key, fn ->
      data =
        Sanbase.Metric.Registry.all()
        |> Sanbase.Metric.Registry.resolve()
        |> remove_hard_deprecated()

      {:ok, data}
    end)
  end

  def get_metrics_from_json() do
    data =
      Sanbase.Clickhouse.MetricAdapter.FileHandler.raw_metrics_json()
      |> Enum.map(fn map ->
        changeset = Sanbase.Metric.Registry.Populate.json_map_to_registry_changeset(map)

        if changeset.valid? do
          changeset |> Ecto.Changeset.apply_changes()
        else
          Logger.error("""
          [#{__MODULE__}] JSON map of metric with error: #{map["name"]}
          Error: #{Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}
          """)
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Sanbase.Metric.Registry.resolve()
      |> remove_hard_deprecated()

    {:ok, data}
  end

  defp get_metrics(attempt \\ 1) do
    case get_metrics_from_registry() do
      {:ok, data} ->
        data

      {:error, _} when attempt <= @max_attempts ->
        Process.sleep(@sleep_time[attempt])
        get_metrics(attempt + 1)

      {:error, _error} ->
        {:ok, data} = get_metrics_from_json()
        data
    end
  end

  def aggregations() do
    Sanbase.Metric.SqlQuery.Helper.aggregations()
  end

  def access_map(), do: get_metrics() |> Map.new(&{&1.metric, &1.access})
  # def table_map(), do: @table_map |> transform()
  # def metrics_mapset(), do: @metrics_mapset |> transform()
  # def aggregation_map(), do: @aggregation_map |> transform()
  # def min_interval_map(), do: @min_interval_map |> transform()
  # def min_plan_map(), do: @min_plan_map |> transform()
  # def name_to_metric_map(), do: @name_to_metric_map |> transform()
  # def docs_links_map(), do: @docs_links_map |> transform()

  # def metric_to_names_map(),
  #   do: @metric_to_names_map |> transform(metric_name_in_map_value_list: true)

  # def human_readable_name_map(), do: @human_readable_name_map |> transform()
  # def metric_version_map(), do: @metric_version_map |> transform()
  # def metrics_data_type_map(), do: @metrics_data_type_map |> transform()
  # def incomplete_data_map(), do: @incomplete_data_map |> transform()
  # def selectors_map(), do: @selectors_map |> transform()
  # def required_selectors_map(), do: @required_selectors_map |> transform()
  # def metrics_label_map(), do: @metrics_label_map |> transform()
  # def deprecated_metrics_map(), do: @deprecated_metrics_map
  # def soft_deprecated_metrics_map(), do: @soft_deprecated_metrics_map
  # def hidden_metrics_mapset(), do: @hidden_metrics_mapset |> transform()
  # def timebound_flag_map(), do: @timebound_flag_map |> transform()

  # def metrics_with_access(level) when level in [:free, :restricted] do
  #   @access_map
  #   |> Enum.filter(fn {_metric, restrictions} ->
  #     Helper.resolve_access_level(restrictions) === level
  #   end)
  #   |> Enum.map(&elem(&1, 0))
  # end

  # def fixed_labels_parameters_metrics_mapset(),
  #   do: @fixed_labels_parameters_metrics_mapset |> transform()

  # def fixed_parameters_map(), do: @fixed_parameters_map |> transform()

  # def metrics_with_data_type(type) do
  #   @metrics_data_type_map
  #   |> transform()
  #   |> Enum.filter(fn {_metric, data_type} -> data_type == type end)
  #   |> Enum.map(&elem(&1, 0))
  # end

  # def name_to_metric(name), do: Map.get(@name_to_metric_map, name)

  defp remove_hard_deprecated(metrics) when is_list(metrics) do
    now = DateTime.utc_now()
    Enum.reject(metrics, fn map -> is_hard_deprecated(map, now) end)
  end

  defp is_hard_deprecated(map, now) do
    hard_deprecate_after = Map.get(map, :hard_deprecate_after, nil)

    not is_nil(hard_deprecate_after) and DateTime.compare(hard_deprecate_after, now) == :lt
  end
end
