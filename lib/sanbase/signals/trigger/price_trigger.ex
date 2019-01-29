defmodule Sanbase.Signals.Trigger.PriceTriggerSettings do
  @derive Jason.Encoder
  @trigger_type "price"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: "price",
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            absolute_threshold: nil,
            repeating: false

  alias __MODULE__

  defimpl Sanbase.Signals.Triggerable, for: PriceTrigger do
    def triggered?(%PriceTrigger{} = _trigger) do
      true
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `repeating` and `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    @spec cache_key(%PriceTrigger{}) :: String.t()
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
