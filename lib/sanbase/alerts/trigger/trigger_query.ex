defmodule Sanbase.Alert.TriggerQuery do
  defmacro trigger_is_not_frozen() do
    quote do
      fragment("""
      trigger->'is_frozen' = 'false'
      """)
    end
  end

  defmacro trigger_is_frozen() do
    quote do
      fragment("""
      trigger->'is_frozen' = 'true'
      """)
    end
  end

  defmacro trigger_type_is(type) do
    quote do
      fragment(
        """
        trigger->'settings'->'type' = ?
        """,
        ^unquote(type)
      )
    end
  end

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

  defmacro trigger_is_public() do
    quote do
      fragment("""
      trigger->>'is_public' = 'true'
      """)
    end
  end

  defmacro trigger_is_active() do
    quote do
      fragment("""
      trigger->>'is_active' = 'true'
      """)
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
