defmodule Sanbase.Alert.Type do
  @moduledoc false
  @type trigger_type :: String.t()
  @type channel :: String.t() | list(String.t() | {String.t(), String.t()})
  @type target :: String.t()
  @type metric :: String.t()
  @type signal :: String.t()
  @type complex_target :: target | list(target) | map()
  @type filtered_target :: %{list: list(), type: trigger_type()}
  @type asset :: String.t()
  @type time_window :: String.t()
  @type payload :: %{} | %{optional(String.t()) => String.t()}
  @type threshold :: number()
  @type percent_threshold :: number()
  @type operation :: map()
  @type extra_explanation :: String.t()
  @type template :: String.t()
  @type kv :: map()
  @type template_kv :: %{} | %{optional(String.t()) => {template(), kv()}}
end
