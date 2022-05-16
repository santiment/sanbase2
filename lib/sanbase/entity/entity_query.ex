defmodule Sanbase.Entity.Query do
  import Ecto.Query

  @doc ~s"""
  Apply a datetime filter, if defined in the opts, to a query.

  This query extension function is defined here and is called with the
  proper arguments from the entity modules' functions.
  """
  @spec maybe_filter_by_cursor(Ecto.Query.t(), atom, Sanbase.Entity.opts()) :: Ecto.Query.t()
  def maybe_filter_by_cursor(query, field, opts) do
    case Keyword.get(opts, :cursor) do
      nil ->
        query

      %{type: :before, datetime: datetime} ->
        from(
          entity in query,
          where: field(entity, ^field) <= ^datetime
        )

      %{type: :after, datetime: datetime} ->
        from(
          entity in query,
          where: field(entity, ^field) >= ^datetime
        )
    end
  end

  @spec maybe_filter_by_users(Ecto.Query.t(), Sanbase.Entity.opts()) :: Ecto.Query.t()
  def maybe_filter_by_users(query, opts) do
    case Keyword.get(opts, :user_ids) do
      nil ->
        query

      user_ids ->
        query
        |> where([ul], ul.user_id in ^user_ids)
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
