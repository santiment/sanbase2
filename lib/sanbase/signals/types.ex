defmodule Sanbase.Signals.Type do
  alias Sanbase.UserLists.UserList

  @type trigger_type :: String.t()
  @type channel :: String.t()
  @type target :: String.t()
  @type complex_target :: target | list(target) | %UserList{}
  @type time_window :: String.t()
  @type payload :: {target, String.t()}
end
