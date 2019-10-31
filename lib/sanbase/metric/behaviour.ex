defmodule Sanbase.Metric.Behaviour do
  @moduledoc ~s"""
  Behaviour describing a metric fetcher
  """

  @type interval :: String.t()
  @type metric :: String.t()
  @type slug :: String.t()
  @type options :: Keyword.t()

  @type metadata :: %{
          metric: metric,
          min_interval: interval(),
          default_aggregation: atom(),
          available_aggregations: list()
        }

  @type timeseries_data_point :: %{datetime: Datetime.t(), value: float()}
  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median

  @callback timeseries_data(
              metric :: metric,
              selector :: any(),
              from :: DatetTime.t(),
              to :: DateTime.t(),
              interval :: interval,
              opts :: Keyword.t()
            ) ::
              {:ok, list(timeseries_data_point)} | {:error, String.t()}

  @callback aggregated_data(
              metric :: metric,
              selector :: any(),
              from :: DatetTime.t(),
              to :: DateTime.t(),
              opts :: options
            ) :: {:ok, list()} | {:error, String.t()}

  @callback first_datetime(metric, slug) ::
              {:ok, DateTime.t()} | {:error, String.t()}

  @callback human_readable_name(metric) :: {:ok, String.t()} | {:error, String.t()}

  @callback metadata(metric) :: {:ok, metadata()} | {:error, String.t()}

  @callback available_aggregations() :: list(aggregation)

  @callback available_slugs() :: {:ok, list(slug)} | {:error, String.t()}

  @callback available_slugs(metric) :: {:ok, list(slug)} | {:error, String.t()}

  @callback available_metrics() :: list(metric)

  @callback free_metrics() :: list(metric)

  @callback restricted_metrics() :: list(metric)

  @callback access_map() :: map()
end
