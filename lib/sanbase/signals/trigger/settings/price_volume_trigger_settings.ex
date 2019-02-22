defmodule Sanbase.Signals.Trigger.PriceVolumeTriggerSettings do
  @derive Jason.Encoder
  @trigger_type "price_volume"
  @enforce_keys [:type, :target, :channel, :time_window, :sensitivity]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            sensitivity: nil
end
