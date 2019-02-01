defmodule Sanbase.Signals.Trigger.PriceTriggerSettings do
  @derive Jason.Encoder
  @trigger_type "price_percent_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false

  alias __MODULE__
  alias Sanbase.Signals.Evaluator.Cache

  @seconds_in_hour 3600
  @seconds_in_day 3600 * 24
  @seconds_in_week 3600 * 24 * 7
  def type(), do: @trigger_type

  defimpl Sanbase.Signals.Triggerable, for: PriceTriggerSettings do
    def triggered?(%PriceTriggerSettings{} = trigger) do
      get_data(trigger) >= trigger.percent_threshold
    end

    def get_data(trigger) do
      price_change_map =
        Cache.get_or_store(
          "price_change_map",
          &Sanbase.Model.Project.List.slug_price_change_map/0
        )

      target_data = Map.get(price_change_map, trigger.target)

      time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(trigger.time_window)

      case time_window_sec do
        @seconds_in_hour ->
          target_data.percent_change_1h || 0

        @seconds_in_day ->
          target_data.percent_change_24h || 0

        @seconds_in_week ->
          target_data.percent_change_7d || 0

        _ ->
          0
      end
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `repeating` and `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PriceTriggerSettings{} = trigger) do
      data = [
        trigger.type,
        trigger.target,
        trigger.time_window,
        trigger.percent_threshold,
        trigger.absolute_threshold
      ]

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end
  end
end

defimpl String.Chars, for: Sanbase.Signals.Trigger.PriceTriggerSettings do
  def to_string(%{} = trigger) do
    "The price of #{trigger.target} has increased by more than #{trigger.percent_threshold} for the past #{
      trigger.time_window
    }"
  end
end
