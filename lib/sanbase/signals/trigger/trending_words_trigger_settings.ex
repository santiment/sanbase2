defmodule Sanbase.Signals.Trigger.TrendingWordsTriggerSettings do
  @derive [Jason.Encoder]
  @trigger_type "trending_words"
  @enforce_keys [:type, :channel, :time_window]
  defstruct type: @trigger_type,
            # ISO8601 string time in UTC
            trigger_time_iso_utc: nil
end
