defmodule Sanbase.Timeline.Order do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.EctoHelper
  alias Sanbase.Repo

  def events_order_limit_preload_query(query, order_by, limit) do
    query
    |> limit(^limit)
    |> order_by_query(order_by)
    |> preload([:user_trigger, [post: :tags], :user_list, :user, :votes])
  end

  defp order_by_query(query, :datetime) do
    from(
      event in query,
      order_by: [desc: event.inserted_at]
    )
  end

  defp order_by_query(query, :author) do
    from(
      event in query,
      join: u in assoc(event, :user),
      order_by: [asc: u.username, desc: event.inserted_at]
    )
  end

  defp order_by_query(query, :votes) do
    # order by: date, votes count, datetime
    ids =
      from(
        entity in query,
        left_join: assoc in assoc(entity, :votes),
        select: {entity.id, fragment("COUNT(?)", assoc.id)},
        group_by: entity.id,
        order_by:
          fragment(
            "?::date DESC, count DESC NULLS LAST, ? DESC",
            entity.inserted_at,
            entity.inserted_at
          )
      )
      |> Repo.all()
      |> Enum.map(fn {id, _} -> id end)

    EctoHelper.by_id_in_order_query(query, ids)
  end

  defp order_by_query(query, :comments) do
    ids = EctoHelper.fetch_ids_ordered_by_assoc_count(query, :comments)
    EctoHelper.by_id_in_order_query(query, ids)
  end
end
