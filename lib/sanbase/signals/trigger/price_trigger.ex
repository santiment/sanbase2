defmodule Sanbase.Signals.Trigger.PriceTrigger do
  @derive Jason.Encoder
  @enforce_keys [:type, :channel, :time_window]
  defstruct type: "price",
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            absolute_threshold: nil,
            repeating: false
end
