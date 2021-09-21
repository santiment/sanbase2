defmodule Sanbase.Metric.Behaviour do
  @moduledoc ~s"""
  Behaviour describing a MetricAdapter module.

  A MetricAdapter module describes how metrics and metadata for them are fetched.
  After a new MetricAdapter module is created, in order to expose it through
  the Sanbase.Metric module, it should be added to the list of modules defined
  in Sanbase.Metric.Helper
  """

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()
  @type opts :: Keyword.t()
  @type available_data_types :: :timeseries | :histogram | :table
  @type threshold :: number()
  @type direction :: :asc | :desc
  @type operator ::
          :greater_than | :less_than | :greater_than_or_equal_to | :less_than_or_equal_to

  @type selector :: slug | map()

  @type metadata :: %{
          metric: metric,
          min_interval: interval(),
          default_aggregation: atom(),
          available_aggregations: list(atom()),
          available_selectors: list(atom()),
          data_type: available_data_types(),
          complexity_weight: number()
        }

  @type histogram_value :: String.t() | float() | integer()
  @type histogram_label :: String.t()

  @type histogram_data_map :: %{
          range: list(float()) | list(DateTime.t()),
          value: float()
        }

  @type histogram_data :: list(histogram_data_map())

  @type table_data_point :: %{
          columns: list(String.t()),
          rows: list(String.t()),
          values: list(list(number()))
        }

  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median

  @type slug_float_value_pair :: %{slug: slug, value: float}

  @type timeseries_data_point :: %{datetime: Datetime.t(), value: float()}

  @type timeseries_data_per_slug_point :: %{
          datetime: Datetime.t(),
          data: list(slug_float_value_pair())
        }

  # Return types
  @type timeseries_data_result :: {:ok, list(timeseries_data_point)} | {:error, String.t()}

  @type aggregated_timeseries_data_result :: {:ok, map()} | {:error, String.t()}

  @type timeseries_data_per_slug_result ::
          {:ok, list(timeseries_data_per_slug_point)} | {:error, String.t()}

  @type table_data_result :: {:ok, table_data_point} | {:error, String.t()}

  @type histogram_data_result :: {:ok, histogram_data} | {:error, String.t()}

  @type slugs_by_filter_result :: {:ok, list(slug())} | {:error, String.t()}

  @type slugs_order_result :: {:ok, list(slug())} | {:error, String.t()}

  @type human_readable_name_result :: {:ok, String.t()} | {:error, String.t()}

  @type first_datetime_result :: {:ok, DateTime.t()} | {:error, String.t()}

  @type last_datetime_computed_at_result :: {:ok, DateTime.t()} | {:error, String.t()}

  @type metadata_result :: {:ok, metadata()} | {:error, String.t()}

  @type available_slugs_result :: {:ok, list(slug)} | {:error, String.t()}

  @type available_metrics_result :: {:ok, list(metric)} | {:error, String.t()}

  @type has_incomplete_data_result :: boolean()

  @type complexity_weight_result :: number()

  @type required_selectors_result :: map()

  # Callbacks

  @callback timeseries_data(
              metric :: metric(),
              selector :: selector,
              from :: DatetTime.t(),
              to :: DateTime.t(),
              interval :: interval(),
              opts :: opts
            ) ::
              timeseries_data_result

  @callback timeseries_data_per_slug(
              metric :: metric(),
              selector :: selector,
              from :: DatetTime.t(),
              to :: DateTime.t(),
              interval :: interval(),
              opts :: opts
            ) ::
              timeseries_data_per_slug_result

  @callback histogram_data(
              metric :: metric(),
              selector :: selector,
              from :: DateTime.t(),
              to :: DateTime.t(),
              interval :: interval(),
              limit :: non_neg_integer()
            ) :: histogram_data_result

  @callback table_data(
              metric :: metric(),
              selector :: selector,
              from :: DateTime.t(),
              to :: DateTime.t(),
              opts :: opts
            ) :: table_data_result

  @callback aggregated_timeseries_data(
              metric :: metric,
              selector :: selector,
              from :: DatetTime.t(),
              to :: DateTime.t(),
              opts :: opts
            ) :: aggregated_timeseries_data_result

  @callback slugs_by_filter(
              metric :: metric,
              from :: DateTime.t(),
              to :: DateTime.t(),
              operator :: operator,
              threshold :: threshold,
              opts :: opts
            ) :: slugs_by_filter_result

  @callback slugs_order(
              metric :: metric,
              from :: DateTime.t(),
              to :: DateTime.t(),
              direction :: direction,
              opts :: opts
            ) :: slugs_order_result

  @callback required_selectors() :: required_selectors_result

  @callback has_incomplete_data?(metric :: metric) :: has_incomplete_data_result

  @callback complexity_weight(metric :: metric) :: complexity_weight_result

  @callback first_datetime(metric, selector) :: first_datetime_result

  @callback last_datetime_computed_at(metric, selector) :: last_datetime_computed_at_result

  @callback human_readable_name(metric) :: human_readable_name_result

  @callback metadata(metric) :: metadata_result

  @callback available_aggregations() :: list(aggregation)

  @callback available_slugs() :: available_slugs_result

  @callback available_slugs(metric) :: available_slugs_result

  @callback available_metrics() :: list(metric)

  @callback available_metrics(selector) :: available_metrics_result()

  @callback available_timeseries_metrics() :: list(metric)

  @callback available_histogram_metrics() :: list(metric)

  @callback available_table_metrics() :: list(metric)

  @callback free_metrics() :: list(metric)

  @callback restricted_metrics() :: list(metric)

  @callback deprecated_metrics_map() :: %{required(String.t()) => String.t()}

  @callback access_map() :: map()

  @callback min_plan_map() :: map()

  @optional_callbacks [
    histogram_data: 6,
    table_data: 5,
    timeseries_data_per_slug: 6,
    deprecated_metrics_map: 0
  ]
end
