defmodule Sanbase.Metric.Behaviour do
  @moduledoc ~s"""
  Behaviour describing a metric fetcher
  """

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()
  @type options :: Keyword.t()
  @type available_data_types :: :timeseries | :histogram

  @type selector :: slug | map()

  @type metadata :: %{
          metric: metric,
          min_interval: interval(),
          default_aggregation: atom(),
          available_aggregations: list(atom()),
          available_selectors: list(atom()),
          data_type: available_data_types()
        }

  @type histogram_value :: String.t() | float() | integer()
  @type histogram_label :: String.t()

  @type histogram_data_map :: %{
          range: list(float()) | list(DateTime.t()),
          value: float()
        }

  @type histogram_data :: list(histogram_data_map())

  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median
  @type operator ::
          :greater_than | :less_than | :greater_than_or_equal_to | :less_than_or_equal_to
  @type timeseries_data_point :: %{datetime: Datetime.t(), value: float()}

  @callback timeseries_data(
              metric :: metric(),
              selector :: selector,
              from :: DatetTime.t(),
              to :: DateTime.t(),
              interval :: interval(),
              aggregation :: aggregation
            ) ::
              {:ok, list(timeseries_data_point)} | {:error, String.t()}

  @callback histogram_data(
              metric :: metric(),
              selector :: selector,
              from :: DateTime.t(),
              to :: DateTime.t(),
              interval :: interval(),
              limit :: non_neg_integer()
            ) :: {:ok, histogram_data} | {:error, String.t()}

  @callback aggregated_timeseries_data(
              metric :: metric,
              selector :: selector,
              from :: DatetTime.t(),
              to :: DateTime.t(),
              aggregation :: aggregation
            ) :: {:ok, map()} | {:error, String.t()}

  @callback slugs_by_filter(
              metric :: metric,
              from :: DateTime.t(),
              to :: DateTime.t(),
              aggregation :: aggregation,
              operator :: operator,
              threshold :: number()
            ) :: {:ok, list(slug())} | {:error, String.t()}

  @callback has_incomplete_data?(metric :: metric) :: true | false

  @callback first_datetime(metric, selector) ::
              {:ok, DateTime.t()} | {:error, String.t()}

  @callback last_datetime_computed_at(metric, selector) ::
              {:ok, DateTime.t()} | {:error, String.t()}

  @callback human_readable_name(metric) :: {:ok, String.t()} | {:error, String.t()}

  @callback metadata(metric) :: {:ok, metadata()} | {:error, String.t()}

  @callback available_aggregations() :: list(aggregation)

  @callback available_slugs() :: {:ok, list(slug)} | {:error, String.t()}

  @callback available_slugs(metric) :: {:ok, list(slug)} | {:error, String.t()}

  @callback available_metrics() :: list(metric)

  @callback available_metrics(selector) :: {:ok, list(metric)} | {:error, String.t()}

  @callback available_timeseries_metrics() :: list(metric)

  @callback available_histogram_metrics() :: list(metric)

  @callback free_metrics() :: list(metric)

  @callback restricted_metrics() :: list(metric)

  @callback access_map() :: map()

  @callback min_plan_map() :: map()

  @optional_callbacks [histogram_data: 6]
end
