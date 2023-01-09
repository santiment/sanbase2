defmodule Sanbase.Accounts.User.Ecto do
  defmacro registration_state_equals(state) do
    quote do
      fragment(
        "registration_state->'state' = ?",
        ^unquote(state)
      )
    end
  end

  defmacro is_registered() do
    quote do
      fragment("registration_state->'state' = ?", ^"finished")
    end
  end
end
