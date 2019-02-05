defmodule Sanbase.Signals.Trigger.PriceTriggerSettings do
  @derive Jason.Encoder
  @trigger_type "price_percent_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  alias __MODULE__
  alias Sanbase.Signals.Evaluator.Cache

  def type(), do: @trigger_type

  defimpl Sanbase.Signals.Triggerable, for: PriceTriggerSettings do
    @seconds_in_hour 3600
    @seconds_in_day 3600 * 24
    @seconds_in_week 3600 * 24 * 7

    def triggered?(%PriceTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceTriggerSettings{} = trigger) do
      percent_change = get_data(trigger)

      case percent_change >= trigger.percent_threshold do
        true ->
          %PriceTriggerSettings{
            trigger
            | triggered?: true,
              payload: trigger_payload(trigger, percent_change)
          }

        _ ->
          %PriceTriggerSettings{trigger | triggered?: false}
      end
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

    defp trigger_payload(trigger, percent_change) do
      "some text"
    end
  end
end
