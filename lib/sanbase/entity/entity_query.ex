defmodule Sanbase.Entity.Query do
  @moduledoc false
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
        where(query, [ul], ul.user_id in ^user_ids)
    end
  end

  @spec maybe_filter_is_featured_query(Ecto.Query.t(), Sanbase.Entity.opts(), Atom.t()) ::
          Ecto.Query.t()
  def maybe_filter_is_featured_query(query, opts, featured_item_field) do
    if Keyword.get(opts, :is_featured_data_only) do
      join(query, :inner, [elem], fi in Sanbase.FeaturedItem, on: elem.id == field(fi, ^featured_item_field))
    else
      query
    end
  end

  @spec maybe_filter_is_hidden(Ecto.Query.t(), Sanbase.Entity.opts()) :: Ecto.Query.t()
  def maybe_filter_is_hidden(query, opts) do
    default_value = Keyword.get(opts, :show_hidden_option, :only_not_hidden)

    # Use this when we introduce a special tab that will be seen by moderators
    # and will be used to undo these actions
    # default_value = if Keyword.get(opts, :is_moderator), do: :hidden_and_not_hidden, else: :only_not_hidden

    case Keyword.get(opts, :show_hidden_entities, default_value) do
      :only_not_hidden ->
        where(query, [elem], elem.is_hidden != true)

      :only_hidden ->
        where(query, [elem], elem.is_hidden == true)

      :hidden_and_not_hidden ->
        query
    end
  end

  def maybe_filter_min_title_length(query, opts, column) do
    case Keyword.get(opts, :min_title_length) do
      len when is_integer(len) and len > 0 ->
        where(query, [elem], fragment("LENGTH(?)", field(elem, ^column)) >= ^len)

      _ ->
        query
    end
  end

  def maybe_filter_min_description_length(query, opts, column) do
    case Keyword.get(opts, :min_description_length) do
      len when is_integer(len) and len > 0 ->
        where(query, [elem], fragment("LENGTH(?)", field(elem, ^column)) >= ^len)

      _ ->
        query
    end
  end

  def default_get_visibility_data(base_query, entity_type, entity_id) do
    query =
      from(entity in base_query,
        where: entity.id == ^entity_id,
        select: %{
          is_public: entity.is_public,
          is_hidden: entity.is_hidden,
          user_id: entity.user_id
        }
      )

    case Sanbase.Repo.one(query) do
      %{} = map ->
        {:ok, map}

      nil ->
        entity_type_str = entity_type |> to_string() |> String.replace("_", " ")
        {:error, "The #{entity_type_str} with id #{entity_id} does not exist"}
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
        WHEN dashboard_id IS NOT NULL THEN dashboard_id
        WHEN query_id IS NOT NULL THEN query_id
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
        WHEN dashboard_id IS NOT NULL THEN 'dashboard'
        WHEN query_id IS NOT NULL THEN 'query'
      END
      """)
    end
  end
end
