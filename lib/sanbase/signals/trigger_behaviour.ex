defmodule Sanbase.Signals.TriggerBehaviour do
  @moduledoc ~s"""
  Each trigger needs to implement this behaviour.
  """

  @callback triggered?(any()) :: list()

  @callback cache_key(any()) :: String.t()
end
