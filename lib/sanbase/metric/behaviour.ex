defmodule Sanbase.Metric.Behaviour do
  @moduledoc ~s"""

  """

  @type metric :: String.t()
  @type slug :: String.t()

  @callback get(
              metric,
              selector :: any(),
              from :: DatetTime.t(),
              to :: DateTime.t(),
              interval :: String.t(),
              opts :: Keyword.t()
            ) ::
              {:ok, list()} | {:error, String.t()}

  @callback first_datetime(metric, slug) ::
              {:ok, DateTime.t()} | {:error, String.t()}

  @callback metadata(metric) :: map()

  @callback available_slugs() :: {:ok, list(slug)} | {:error, String.t()}

  @callback available_metrics() :: {:ok, list(metric)}

  @callback free_metrics() :: {:ok, list(metric)}

  @callback restricted_metrics() :: {:ok, list(metric)}
end
