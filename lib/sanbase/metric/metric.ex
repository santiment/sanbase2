defmodule Sanbase.Metric do
  @moduledoc """
  Dispatch module
  TODO DOCS
  """

  alias Sanbase.Clickhouse

  @metric_modules [
    Clickhouse.Github.MetricAdapter,
    Clickhouse.Metric
  ]

  Module.register_attribute(__MODULE__, :available_aggregations_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :free_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :restricted_metrics_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :access_map_acc, accumulate: true)
  Module.register_attribute(__MODULE__, :metric_module_mapping_acc, accumulate: true)

  for module <- @metric_modules do
    @available_aggregations_acc module.available_aggregations()
    @free_metrics_acc module.free_metrics()
    @restricted_metrics_acc module.restricted_metrics()
    @access_map_acc module.access_map()
    @metric_module_mapping_acc Enum.map(
                                 module.available_metrics(),
                                 fn metric -> %{metric: metric, module: module} end
                               )
  end

  @available_aggregations List.flatten(@available_aggregations_acc) |> Enum.uniq()
  @free_metrics List.flatten(@free_metrics_acc) |> Enum.uniq()
  @restricted_metrics List.flatten(@restricted_metrics_acc) |> Enum.uniq()
  @metrics_module_mapping List.flatten(@metric_module_mapping_acc) |> Enum.uniq()
  @access_map Enum.reduce(@access_map_acc, %{}, fn map, acc -> Map.merge(map, acc) end)

  @metrics Enum.map(@metrics_module_mapping, & &1.metric)

  @doc ~s"""

  """
  def get(metric, identifier, from, to, interval, opts \\ [])

  @doc ~s"""

  """
  def get_aggregated(metric, identifier, from, to, opts \\ [])

  for %{metric: metric, module: module} <- @metrics_module_mapping do
    def get(unquote(metric), identifier, from, to, interval, aggregation) do
      unquote(module).get(
        unquote(metric),
        identifier,
        from,
        to,
        interval,
        aggregation
      )
    end

    def get_aggregated(unquote(metric), identifier, from, to, aggregation) do
      unquote(module).get_aggregated(
        unquote(metric),
        identifier,
        from,
        to,
        aggregation
      )
    end

    def human_readable_name(unquote(metric)) do
      unquote(module).human_readable_name(unquote(metric))
    end

    def metadata(unquote(metric)) do
      unquote(module).metadata(unquote(metric))
    end

    def first_datetime(unquote(metric), slug) do
      unquote(module).first_datetime(unquote(metric), slug)
    end

    def available_slugs(unquote(metric)) do
      unquote(module).available_slugs(unquote(metric))
    end
  end

  def get(metric, _, _, _, _, _), do: {:error, "The '#{metric}' metric is not supported."}
  def metadata(metric), do: {:error, "The '#{metric}' metric is not supported."}
  def first_datetime(metric, _), do: {:error, "The '#{metric}' metric is not supported."}

  @doc ~s"""
  TODO
  """
  def available_aggregations(), do: @available_aggregations

  @doc ~s"""
  TODO
  """
  def available_metrics(), do: @metrics

  @doc ~s"""
  TODO
  """
  def available_slugs_all_metrics() do
    Sanbase.Cache.get_or_store({:metric_available_slugs_all_metrics, 1800}, fn ->
      {slugs, errors} =
        Enum.reduce(@metric_modules, {[], []}, fn module, {slugs_acc, errors} ->
          case module.available_slugs() do
            {:ok, slugs} -> {[slugs | slugs_acc], errors}
            {:error, error} -> {slugs_acc, [error | errors]}
          end
        end)

      case errors do
        [] -> slugs |> Enum.uniq()
        _ -> {:error, "Cannot fetch all available slugs"}
      end
    end)
  end

  @doc ~s"""
  TODO
  """
  def free_metrics(), do: @free_metrics

  @doc ~s"""
  TODO
  """
  def restricted_metrics(), do: @restricted_metrics

  @doc ~s"""
  TODO
  """
  def access_map(), do: @access_map
end
