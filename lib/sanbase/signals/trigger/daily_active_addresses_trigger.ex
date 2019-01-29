defmodule Sanbase.Signals.Trigger.DailyActiveAddressesTriggerSettings do
  @derive [Jason.Encoder]
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :time_window, :percent_threshold]
  defstruct type: "daily_active_addresses",
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false

  alias __MODULE__

  defimpl Sanbase.Signals.Triggerable, for: DailyActiveAddressesTrigger do
    def triggered?(%DailyActiveAddressesTrigger{} = _trigger) do
      true
    end

    def cache_key(%DailyActiveAddressesTrigger{} = trigger) do
      data =
        [trigger.type, trigger.target, trigger.time_window, trigger.percent_threshold]
        |> Jason.encode!()

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end
  end

  defimpl String.Chars, for: DailyActiveAddressesTrigger do
    def to_string(%{} = trigger) do
      "example payload for #{trigger.type}"
    end
  end
end
