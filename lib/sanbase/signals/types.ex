defmodule Sanbase.Signals.Type do
  @type trigger_type :: String.t()
  @type channel :: String.t()
  @type target :: String.t()
  @type complex_target :: target | list(target) | map()
  @type filtered_target :: %{list: list(), type: trigger_type()}
  @type asset :: String.t()
  @type time_window :: String.t()
  @type payload :: %{} | %{optional(String.t()) => String.t()}
  @type threshold :: number()
  @type percent_threshold :: number()
  @type operation :: map()
end
