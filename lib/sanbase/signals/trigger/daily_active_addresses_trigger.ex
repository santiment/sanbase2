defmodule Sanbase.Signals.Trigger.DailyActiveAddressesTriggerSettings do
  @derive [Jason.Encoder]
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :time_window, :percent_threshold]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            # string - '1h', '1d'
            time_window: nil,
            percent_threshold: nil,
            repeating: false
end
