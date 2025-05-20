defmodule Sanbase.Accounts.User.Ecto do
  defmacro is_registered() do
    quote do
      fragment("registration_state->'state' = ?", ^"finished")
    end
  end
end
