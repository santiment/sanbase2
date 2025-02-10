defmodule Sanbase.Alert.Trigger.DailyMetricTriggerSettings do
  @moduledoc ~s"""
  An alert based on the V2 ClickHouse metrics.

  The metric we're following is configured via the 'metric' parameter
  """
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.Alert.Validation
  import Sanbase.Validation

  alias __MODULE__
  alias Sanbase.Alert.Trigger.DailyMetricTriggerSettings
  alias Sanbase.Alert.Type

  @trigger_type "daily_metric_signal"
  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @enforce_keys [:type, :metric, :target, :channel, :operation]
  defstruct type: @trigger_type,
            metric: nil,
            target: nil,
            channel: nil,
            time_window: "1d",
            operation: nil,
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            extra_explanation: nil,
            template: nil,
            payload: %{},
            template_kv: %{}

  validates(:metric, &valid_metric?/1)
  validates(:metric, &valid_above_5m_min_interval_metric?/1)
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

  @spec type() :: Type.trigger_type()
  def type, do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  defimpl Sanbase.Alert.Settings, for: DailyMetricTriggerSettings do
    alias Sanbase.Alert.Trigger.MetricTriggerHelper

    def triggered?(%DailyMetricTriggerSettings{} = settings), do: MetricTriggerHelper.triggered?(settings)

    def cache_key(%DailyMetricTriggerSettings{} = settings), do: MetricTriggerHelper.cache_key(settings)

    def evaluate(%DailyMetricTriggerSettings{} = settings, trigger), do: MetricTriggerHelper.evaluate(settings, trigger)
  end
end
