defmodule Sanbase.Signal.History.MetricHistory do
  @moduledoc """
  Implementation of historical_trigger_points for the generic metric signal.
  Currently it is bucketed in `1 day` intervals and goes 90 days back.
  """

  alias Sanbase.Signal.Trigger.MetricTriggerSettings

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          current: float(),
          absolute_change: float(),
          percent_change: float(),
          triggered?: boolean()
        }

  defimpl Sanbase.Signal.History, for: MetricTriggerSettings do
    import Sanbase.DateTimeUtils, only: [str_to_days: 1]

    alias Sanbase.Signal.History.ResultBuilder
    alias Sanbase.Signal.History.MetricHistory

    @historical_days_from 90
    @historical_days_interval "1d"

    @spec historical_trigger_points(%MetricTriggerSettings{}, String.t()) ::
            {:ok, list(MetricHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %MetricTriggerSettings{target: %{slug: slug}} = settings,
          cooldown
        )
        when is_binary(slug) do
      %MetricTriggerSettings{metric: metric, time_window: time_window} = settings

      case get_data(metric, slug, time_window) do
        {:ok, data} -> ResultBuilder.build(data, settings, cooldown, value_key: :value)
        {:error, error} -> {:error, error}
      end
    end

    def get_data(metric, slug, time_window) when is_binary(slug) do
      to = Timex.now()
      shift = @historical_days_from + str_to_days(time_window) - 1

      Sanbase.Metric.timeseries_data(
        metric,
        slug,
        Timex.shift(to, days: -shift),
        to,
        @historical_days_interval
      )
    end
  end
end
