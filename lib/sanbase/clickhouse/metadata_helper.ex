defmodule Sanbase.Clickhouse.MetadataHelper do
  @moduledoc ~s"""
  Provides some helper functions for fetching metrics, assets and
  anomalies metadata from ClickHouse
  """

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.Clickhouse.MetricAdapter.Registry
  alias Sanbase.Clickhouse.Query
  alias Sanbase.ClickhouseRepo

  # Map from the names used in ClickHouse to the publicly exposed ones.
  # Example: stack_circulation_20y -> circulation

  def slug_to_asset_id_map do
    cache_key = Sanbase.Cache.hash({__MODULE__, __ENV__.function})

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      query_struct =
        Query.new("SELECT toUInt32(asset_id), name FROM asset_metadata", %{})

      ClickhouseRepo.query_reduce(query_struct, %{}, fn [asset_id, slug], acc ->
        Map.put(acc, slug, asset_id)
      end)
    end)
  end

  def asset_id_to_slug_map do
    cache_key = Sanbase.Cache.hash({__MODULE__, __ENV__.function})

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      case slug_to_asset_id_map() do
        {:ok, data} ->
          {:ok, Map.new(data, fn {k, v} -> {v, k} end)}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def metric_name_to_metric_id_map do
    cache_key = Sanbase.Cache.hash({__MODULE__, __ENV__.function})
    Sanbase.Cache.get_or_store({cache_key, 600}, &get_metric_name_to_metric_id_map/0)
  end

  def metric_id_to_metric_name_map do
    cache_key = Sanbase.Cache.hash({__MODULE__, __ENV__.function})
    Sanbase.Cache.get_or_store({cache_key, 600}, &get_metric_id_to_metric_name_map/0)
  end

  # Private functions

  defp get_metric_name_to_metric_id_map do
    query_struct =
      Query.new("SELECT toUInt32(metric_id), name FROM metric_metadata", %{})

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [metric_id, name], acc ->
      names = Map.get(Registry.metric_to_names_map(), name, [name])

      Enum.reduce(names, acc, fn inner_name, inner_acc ->
        Map.put(inner_acc, inner_name, metric_id)
      end)
    end)
  end

  defp get_metric_id_to_metric_name_map do
    maybe_apply_function(metric_name_to_metric_id_map(), fn data ->
      Enum.reduce(data, %{}, fn {name, id}, acc ->
        Map.update(acc, id, [name], fn list -> [name | list] end)
      end)
    end)
  end
end
