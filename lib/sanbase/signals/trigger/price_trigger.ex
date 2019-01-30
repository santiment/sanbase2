defmodule Sanbase.Signals.Trigger.PriceTriggerSettings do
  @derive Jason.Encoder
  @trigger_type "price"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: "price_percent_change",
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false

  alias __MODULE__
  alias Sanbase.Signals.Evaluator.Cache

  defimpl Sanbase.Signals.Triggerable, for: PriceTrigger do
    def triggered?(%PriceTrigger{} = trigger) do
      get_data(trigger) >= trigger.percent_threshold
    end

    def get_data(trigger) do
      price_change_map =
        Cache.get_or_store(
          "price_change_map",
          &Sanbase.Model.Project.List.slug_price_change_map/0
        )

      target_data = Map.get(price_change_map, trigger.target)

      case trigger.time_window do
        "1h" ->
          target_data.percent_change_1h

        "24h" ->
          target_data.percent_change_24h

        _ ->
          -1
      end
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `repeating` and `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PriceTrigger{} = trigger) do
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

defimpl String.Chars, for: Sanbase.Signals.Trigger.PriceTrigger do
  def to_string(%{} = trigger) do
    "example payload for #{trigger.type}, [](s3_path)"
  end
end
