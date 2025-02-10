defmodule Sanbase.Alert.TriggerQuery do
  @moduledoc false
  defmacro trigger_is_not_frozen() do
    quote do
      fragment("""
      trigger->'is_frozen' = 'false'
      """)
    end
  end

  defmacro trigger_frozen?() do
    quote do
      fragment("""
      trigger->'is_frozen' = 'true'
      """)
    end
  end

  defmacro trigger_type_equals?(type) do
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

  defmacro public_trigger?() do
    quote do
      fragment("""
      trigger->>'is_public' = 'true'
      """)
    end
  end

  defmacro slug_trigger_target?(slugs) do
    quote do
      fragment(
        """
        trigger->'settings'->'target'->'slug' = ANY(?)
        """,
        ^unquote(slugs)
      )
    end
  end

  defmacro trigger_active?() do
    quote do
      fragment("""
      trigger->>'is_active' = 'true'
      """)
    end
  end
end
