defmodule Sanbase.Signals.Trigger.DailyActiveAddressesTrigger do
  @enforce_keys [:type, :channel, :time_window, :percent_threshold]
  defstruct type: "daily_active_addresses",
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false
end
