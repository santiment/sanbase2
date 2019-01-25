defmodule Sanbase.Signals.Trigger.DaaTrigger do
  @enforce_keys [:type, :channel, :time_window, :percent_threshold]
  defstruct type: "daa",
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false
end
