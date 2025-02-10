defmodule Sanbase.Alert.History.MetricHistory do
  @moduledoc """
  Implementation of historical_trigger_points for the generic metric alert.
  Currently it is bucketed in `1 day` intervals and goes 90 days back.
  """

  alias Sanbase.Alert.Trigger.DailyMetricTriggerSettings
  alias Sanbase.Alert.Trigger.MetricTriggerSettings

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          current: float(),
          absolute_change: float(),
          percent_change: float(),
          triggered?: boolean()
        }

  defimpl Sanbase.Alert.History, for: [MetricTriggerSettings, DailyMetricTriggerSettings] do
    import Sanbase.DateTimeUtils, only: [str_to_days: 1]

    alias Sanbase.Alert.History.MetricHistory
    alias Sanbase.Alert.History.ResultBuilder

    @historical_days_from 90
    @historical_days_interval "1d"

    defguard has_binary_key?(map, key)
             when is_map(map) and is_map_key(map, key) and is_binary(:erlang.map_get(key, map))

    @spec historical_trigger_points(map(), String.t()) ::
            {:ok, list(MetricHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(%{target: target} = settings, cooldown)
        when has_binary_key?(target, :slug) or has_binary_key?(target, :text) do
      %{metric: metric, time_window: time_window} = settings

      case get_data(metric, target, time_window) do
        {:ok, data} -> ResultBuilder.build(data, settings, cooldown, value_key: :value)
        {:error, error} -> {:error, error}
      end
    end

    def historical_trigger_points(%{target: target}, _) do
      {:error,
       """
       Target must be a single slug in the format '{slug: "single_string_slug"}' or
       text in the format '{text: "buy OR sell"}'. Got #{inspect(target)} instead.
       """}
    end

    def get_data(metric, target, time_window) do
      to = DateTime.utc_now()
      shift = @historical_days_from + str_to_days(time_window) - 1

      Sanbase.Metric.timeseries_data(
        metric,
        target,
        Timex.shift(to, days: -shift),
        to,
        @historical_days_interval
      )
    end
  end
end
