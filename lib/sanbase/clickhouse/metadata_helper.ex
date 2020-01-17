defmodule Sanbase.Clickhouse.MetadataHelper do
  @moduledoc ~s"""
  Provides some helper functions for fetching metrics, assets and
  anomalies metadata from ClickHouse
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def slug_to_asset_id_map() do
    Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function}, fn ->
      query = "SELECT toUInt32(asset_id), name FROM asset_metadata"
      args = []

      ClickhouseRepo.query_reduce(query, args, %{}, fn [asset_id, slug], acc ->
        Map.put(acc, slug, asset_id)
      end)
    end)
  end

  def asset_id_to_slug_map() do
    Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function}, fn ->
      case slug_to_asset_id_map() do
        {:ok, data} ->
          {:ok, data |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, v, k) end)}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def metric_name_to_metric_id_map() do
    Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function}, fn ->
      metric_version_map = Sanbase.Clickhouse.Metric.FileHandler.metric_version_map()

      query = "SELECT toUInt32(metric_id), name, version FROM metric_metadata"
      args = []

      ClickhouseRepo.query_reduce(query, args, %{}, fn [metric_id, name, version], acc ->
        case Map.get(metric_version_map, name) do
          ^version -> Map.put(acc, name, metric_id)
          _ -> acc
        end
      end)
    end)
  end
end
