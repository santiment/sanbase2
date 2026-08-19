defmodule Sanbase.Clickhouse.MetricAdapter.FileHandler do
  @moduledoc false

  # Structure
  #  This JSON file contains a list of metrics available in ClickHouse. For every metric:
  #  metric - the original metric name, as used in the ClickHouse metric_metadata table
  #  alias - the more user-friendly name the metric is exposed under by the API
  #  access - whether the metric is completely free or time restrictions apply
  #  aggregation - the default aggregation combining values when the data is queried with
  #    an interval bigger than 'min_interval'
  #  min-interval - the minimal interval the data is available for
  #  table - the ClickHouse table the metric is stored in
  # Ordering
  #  The order is not important. For readability the same metric with different time-bounds
  #  is packed together, from the biggest time-bound to the smallest. `time-bound` means the
  #  metric counts only the coins/tokens that moved in the past N days/years.

  # @external_resource is registered with `accumulate: true`, so it holds all files
  path_to = fn file -> Path.join([__DIR__, "metric_files", file]) end
  path_to_deprecated = fn file -> Path.join([__DIR__, "metric_files", "deprecated", file]) end

  @external_resource path_to.("available_v2_metrics.json")
  @external_resource path_to.("change_metrics.json")
  @external_resource path_to.("defi_metrics.json")
  @external_resource path_to.("derivatives_metrics.json")
  @external_resource path_to.("eth2_metrics.json")
  @external_resource path_to.("exchange_metrics.json")
  @external_resource path_to.("ecosystem_aggregated_metrics.json")
  @external_resource path_to.("histogram_metrics.json")
  @external_resource path_to.("holders_metrics.json")
  @external_resource path_to.("label_based_metric_metrics.json")
  @external_resource path_to.("labeled_balance_metrics.json")
  @external_resource path_to.("labeled_intraday_metrics.json")
  @external_resource path_to.("makerdao_metrics.json")
  @external_resource path_to.("social_metrics.json")
  @external_resource path_to.("table_structured_metrics.json")
  @external_resource path_to.("uniswap_metrics.json")
  @external_resource path_to.("labeled_holders_distribution_metrics.json")
  @external_resource path_to.("active_holders_metrics.json")
  @external_resource path_to.("fixed_parameters_labelled_balance_metrics.json")

  # Hidden metrics
  # These metrics are available for fetching, but they do not appear in any
  # available metrics API calls
  @external_resource path_to.("hidden_social_metrics.json")

  # Deprecated metrics
  @external_resource path_to_deprecated.("deprecated_change_metrics.json")
  @external_resource path_to_deprecated.("deprecated_labeled_between_labels_flow_metrics.json")
  @external_resource path_to_deprecated.("deprecated_labeled_exchange_flow_metrics.json")
  @external_resource path_to_deprecated.("deprecated_social_metrics.json")

  @raw_metrics_json Enum.reduce(
                      @external_resource,
                      [],
                      fn file, acc ->
                        try do
                          (File.read!(file) |> Jason.decode!()) ++ acc
                        rescue
                          e in [Jason.DecodeError] ->
                            IO.warn("Jason decoding error in file #{file}")
                            reraise e, __STACKTRACE__
                        end
                      end
                    )
  def raw_metrics_json(), do: @raw_metrics_json
end
