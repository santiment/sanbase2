defmodule Sanbase.Alert.Trigger.MetricTriggerSettings do
  @moduledoc ~s"""
  An alert based on the V2 ClickHouse metrics.

  The metric we're following is configured via the 'metric' parameter
  """

  use Vex.Struct
  use Sanbase.Alert.Trigger.Settings.TriggerSettingsBase, trigger_type: "metric_signal"

  import Sanbase.{Validation, Alert.Validation}

  alias __MODULE__
  alias Sanbase.Alert.Type

  @enforce_keys [:type, :metric, :target, :channel, :operation]
  defstruct [
              type: @trigger_type,
              metric: nil,
              target: nil,
              channel: nil,
              time_window: "1d",
              operation: nil,
              extra_explanation: nil,
              template: nil
            ] ++ TriggerSettingsBase.private_struct_fields()

  validates(:metric, &valid_metric?/1)
  validates(:metric, &valid_5m_min_interval_metric?/1)
  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:operation, &valid_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          metric: Type.metric(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          operation: Type.operation(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          extra_explanation: Type.extra_explanation(),
          template: Type.template(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  defimpl Sanbase.Alert.Settings, for: MetricTriggerSettings do
    alias Sanbase.Alert.Trigger.MetricTriggerHelper

    def triggered?(%MetricTriggerSettings{} = settings),
      do: MetricTriggerHelper.triggered?(settings)

    def cache_key(%MetricTriggerSettings{} = settings),
      do: MetricTriggerHelper.cache_key(settings)

    def evaluate(%MetricTriggerSettings{} = settings, trigger),
      do: MetricTriggerHelper.evaluate(settings, trigger)
  end
end
