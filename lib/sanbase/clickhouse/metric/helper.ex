defmodule Sanbase.Clickhouse.Metric.Helper do
  @moduledoc ~s"""
  Provides some helper functions for filtering the clickhouse v2 metrics
  """
  alias Sanbase.Clickhouse.Metric
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  def slug_asset_id_map() do
    Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function}, fn ->
      query = "SELECT toUInt32(asset_id), name FROM asset_metadata"
      args = []

      ClickhouseRepo.query_reduce(query, args, %{}, fn [asset_id, slug], acc ->
        Map.put(acc, slug, asset_id)
      end)
    end)
  end

  def asset_id_slug_map() do
    Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function}, fn ->
      case slug_asset_id_map() do
        {:ok, data} ->
          {:ok, data |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, v, k) end)}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  def metric_name_id_map() do
    Sanbase.Cache.get_or_store({__MODULE__, __ENV__.function}, fn ->
      query = "SELECT toUInt32(metric_id), name FROM metric_metadata"
      args = []

      ClickhouseRepo.query_reduce(query, args, %{}, fn [metric_id, name], acc ->
        Map.put(acc, name, metric_id)
      end)
    end)
  end

  def metric_with_name_containing(str) do
    Metric.available_metrics()
    |> Enum.filter(fn metric -> String.contains?(metric, str) end)
  end

  def mvrv_metrics(), do: metric_with_name_containing("mvrv") |> wrap()
  def realized_value_metrics(), do: metric_with_name_containing("realized") |> wrap()
  def token_age_consumed_metrics(), do: metric_with_name_containing("age_consumed") |> wrap()

  defp wrap(list) do
    list
    |> Enum.map(fn mvrv ->
      {:clickhouse_v2_metric, String.to_atom(mvrv)}
    end)
  end
end
