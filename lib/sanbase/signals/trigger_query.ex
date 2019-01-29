defmodule Sanbase.Signals.TriggerQuery do
  defmacro trigger_by_id(id) do
    quote do
      fragment(
        """
        trigger->>'id' = ?
        """,
        ^unquote(id)
      )
    end
  end

  defmacro trigger_id_one_of(ids) do
    quote do
      fragment(
        """
        trigger->>'id' = ANY(?)
        """,
        ^unquote(ids)
      )
    end
  end
end
