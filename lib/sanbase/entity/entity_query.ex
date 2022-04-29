defmodule Sanbase.Entity.Query do
  defmacro entity_id_and_type_selection() do
    quote do
      %{
        entity_id:
          fragment("""
          CASE
            WHEN post_id IS NOT NULL THEN post_id
            WHEN watchlist_id IS NOT NULL THEN watchlist_id
            WHEN chart_configuration_id IS NOT NULL THEN chart_configuration_id
            WHEN user_trigger_id IS NOT NULL THEN user_trigger_id
          END
          """),
        entity_type:
          fragment("""
          CASE
            WHEN post_id IS NOT NULL THEN 'insight'
            -- the watchlist_id can point to either screener or watchlist. This is handled later.
            WHEN watchlist_id IS NOT NULL THEN 'watchlist'
            WHEN chart_configuration_id IS NOT NULL THEN 'chart_configuration'
            WHEN user_trigger_id IS NOT NULL THEN 'user_trigger'
          END
          """)
      }
    end
  end

  defmacro entity_id_selection() do
    quote do
      fragment("""
      CASE
        WHEN post_id IS NOT NULL THEN post_id
        WHEN watchlist_id IS NOT NULL THEN watchlist_id
        WHEN chart_configuration_id IS NOT NULL THEN chart_configuration_id
        WHEN user_trigger_id IS NOT NULL THEN user_trigger_id
      END
      """)
    end
  end

  defmacro entity_type_selection() do
    quote do
      fragment("""
      CASE
        WHEN post_id IS NOT NULL THEN 'insight'
        -- the watchlist_id can point to either screener or watchlist. This is handled later.
        WHEN watchlist_id IS NOT NULL THEN 'watchlist'
        WHEN chart_configuration_id IS NOT NULL THEN 'chart_configuration'
        WHEN user_trigger_id IS NOT NULL THEN 'user_trigger'
      END
      """)
    end
  end
end
