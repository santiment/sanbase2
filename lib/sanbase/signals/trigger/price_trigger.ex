defmodule Sanbase.Signals.Trigger.PriceTriggerSettings do
  @derive Jason.Encoder
  @trigger_type "price"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            absolute_threshold: nil,
            repeating: false
end
