defmodule Sanbase.Contract.MetricAdapter do
  @moduledoc ~s"""
  Module for exposing raw contract metrics.

  This module exposes metrics that are computed on-the-fly
  for a contract without requiring us to have a bigdata pipeline
  that computes them.
  """

  @behaviour Sanbase.Metric.Behaviour

  import Sanbase.Utils.Transform
  import Sanbase.Contract.MetricAdapter.SqlQuery

  @metrics ["contract_transactions_count", "contract_interacting_addresses_count"]
  @timeseries_metrics @metrics
  @histogram_metrics []
  @table_metrics []

  # plan related - the plan is upcase string
  @min_plan_map Enum.into(@metrics, %{}, fn metric -> {metric, "FREE"} end)

  # restriction related - the restriction is atom :free or :restricted
  @access_map Enum.into(@metrics, %{}, fn metric -> {metric, :restricted} end)
  @free_metrics Enum.filter(@access_map, &match?({_, :free}, &1)) |> Enum.map(&elem(&1, 0))
  @restricted_metrics Enum.filter(@access_map, &match?({_, :restricted}, &1))
                      |> Enum.map(&elem(&1, 0))

  @required_selectors Enum.into(@metrics, %{}, &{&1, [[:contract_address]]})
  @default_complexity_weight 1.0
  @aggregations [:count]

  alias Sanbase.ChRepo

  @impl Sanbase.Metric.Behaviour
  def has_incomplete_data?(_metric), do: false

  @impl Sanbase.Metric.Behaviour
  def complexity_weight(_metric), do: @default_complexity_weight

  @impl Sanbase.Metric.Behaviour
  def required_selectors(), do: @required_selectors

  @impl Sanbase.Metric.Behaviour
  def broken_data(_metric, _selector, _from, _to), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def timeseries_data(metric, %{contract_address: contract_address}, from, to, interval, _opts)
      when is_binary(contract_address) do
    timeseries_data_query(metric, contract_address, from, to, interval)
    |> ChRepo.query_transform(fn [unix, value] ->
      %{
        datetime: DateTime.from_unix!(unix),
        value: value
      }
    end)
  end

  @impl Sanbase.Metric.Behaviour
  def aggregated_timeseries_data(metric, _selector, _from, _to, _opts) do
    not_implemented_error("aggregated_timeseries_data", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def timeseries_data_per_slug(metric, _selector, _from, _to, _interval, _opts) do
    not_implemented_error("timeseries_data_per_slug", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_by_filter(metric, _from, _to, _operator, _threshold, _opts) do
    not_implemented_error("slugs_by_filter", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def slugs_order(metric, _from, _to, _direction, _opts) do
    not_implemented_error("slugs_order", metric)
  end

  @impl Sanbase.Metric.Behaviour
  def first_datetime(_metric, %{contract_address: contract_address})
      when is_binary(contract_address) do
    query_struct = first_datetime_query(contract_address)

    ChRepo.query_transform(query_struct, fn [unix] ->
      DateTime.from_unix!(unix)
    end)
    |> maybe_unwrap_ok_value()
  end

  @impl Sanbase.Metric.Behaviour
  def last_datetime_computed_at(_metric, %{contract_address: contract_address})
      when is_binary(contract_address) do
    query_struct = last_datetime_computed_at_query(contract_address)

    ChRepo.query_transform(query_struct, fn [unix] -> DateTime.from_unix!(unix) end)
    |> maybe_unwrap_ok_value()
  end

  @impl Sanbase.Metric.Behaviour
  def metadata(metric) do
    {:ok,
     %{
       metric: metric,
       internal_metric: metric,
       has_incomplete_data: has_incomplete_data?(metric),
       min_interval: "1m",
       default_aggregation: :count,
       available_aggregations: @aggregations,
       available_selectors: [:contract_address],
       required_selectors: [:contract_address],
       data_type: :timeseries,
       is_timebound: false,
       complexity_weight: @default_complexity_weight,
       docs: [],
       is_label_fqn_metric: false,
       is_deprecated: false,
       hard_deprecate_after: nil
     }}
  end

  @impl Sanbase.Metric.Behaviour
  def human_readable_name(metric) do
    case metric do
      "contract_transactions_count" ->
        {:ok, "Contract Transactions Count"}

      "contract_interacting_addresses_count" ->
        {:ok, "Contract Interacting Addresses Count"}
    end
  end

  @impl Sanbase.Metric.Behaviour
  def access_map(), do: @access_map

  @impl Sanbase.Metric.Behaviour
  def min_plan_map(), do: @min_plan_map

  @impl Sanbase.Metric.Behaviour
  def available_aggregations(), do: @aggregations

  @impl Sanbase.Metric.Behaviour
  def incomplete_metrics(), do: []

  @impl Sanbase.Metric.Behaviour
  def free_metrics(), do: @free_metrics

  @impl Sanbase.Metric.Behaviour
  def restricted_metrics(), do: @restricted_metrics

  @impl Sanbase.Metric.Behaviour
  def available_timeseries_metrics(), do: @timeseries_metrics

  @impl Sanbase.Metric.Behaviour
  def available_histogram_metrics(), do: @histogram_metrics

  @impl Sanbase.Metric.Behaviour
  def available_table_metrics(), do: @table_metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(), do: @metrics

  @impl Sanbase.Metric.Behaviour
  def available_metrics(%{contract_address: _}), do: {:ok, @metrics}
  def available_metrics(%{slug: _}), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def available_slugs(), do: {:ok, []}

  @impl Sanbase.Metric.Behaviour
  def available_slugs(_metric), do: available_slugs()

  # Private functions

  defp not_implemented_error(function, metric) do
    {:error, "The #{function} function is not implemented for #{metric}"}
  end
end
