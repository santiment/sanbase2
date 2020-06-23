defmodule Sanbase.Clickhouse.MetadataHelper do
  @moduledoc ~s"""
  Provides some helper functions for fetching metrics, assets and
  anomalies metadata from ClickHouse
  """

  alias Sanbase.ClickhouseRepo

  # Map from the names used in ClickHouse to the publicly exposed ones.
  # Example: stack_circulation_20y -> circulation
  @original_name_to_metric_name Sanbase.Clickhouse.Metric.FileHandler.name_to_metric_map()
                                |> Enum.into(%{}, fn {k, v} -> {v, k} end)

  def slug_to_asset_id_map() do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      query = "SELECT toUInt32(asset_id), name FROM asset_metadata"
      args = []

      ClickhouseRepo.query_reduce(query, args, %{}, fn [asset_id, slug], acc ->
        Map.put(acc, slug, asset_id)
      end)
    end)
  end

  def asset_id_to_slug_map() do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      case slug_to_asset_id_map() do
        {:ok, data} ->
          {:ok, data |> Enum.into(%{}, fn {k, v} -> {v, k} end)}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def metric_name_to_metric_id_map() do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      query = "SELECT toUInt32(metric_id), name FROM metric_metadata"
      args = []

      ClickhouseRepo.query_reduce(query, args, %{}, fn [metric_id, name], acc ->
        name = Map.get(@original_name_to_metric_name, name, name)
        Map.put(acc, name, metric_id)
      end)
    end)
  end

  def metric_id_to_metric_name_map() do
    cache_key = {__MODULE__, __ENV__.function} |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      case metric_name_to_metric_id_map() do
        {:ok, data} ->
          {:ok, data |> Enum.into(%{}, fn {k, v} -> {v, k} end)}

        {:error, error} ->
          {:error, error}
      end
    end)
  end
end
