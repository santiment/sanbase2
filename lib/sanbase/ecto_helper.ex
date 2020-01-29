defmodule Sanbase.EctoHelper do
  @moduledoc """
  Module with reusable Ecto helper queries.
  """

  import Ecto.Query

  alias Sanbase.Repo

  @doc """
  Fetch a list of ids ordered by the count of items in has_many/many_to_many association.
  """
  @spec fetch_ids_ordered_by_assoc_count(Ecto.Query.t(), atom, Keyword.t()) ::
          list(non_neg_integer())
  def fetch_ids_ordered_by_assoc_count(query, assoc_table, opts \\ []) do
    order_by_second = Keyword.get(opts, :order_by, :inserted_at)

    from(
      entity in query,
      left_join: assoc in assoc(entity, ^assoc_table),
      select: {entity.id, fragment("COUNT(?)", assoc.id)},
      group_by: entity.id,
      order_by: fragment("count DESC NULLS LAST, ? DESC", field(entity, ^order_by_second))
    )
    |> Repo.all()
    |> Enum.map(fn {id, _} -> id end)
  end

  @doc """
  Fetch records of entity by a list of ids and keep the order of the selected records same as the list.
  """
  @spec by_id_in_order_query(Ecto.Query.t(), list(non_neg_integer())) :: Ecto.Query.t()
  def by_id_in_order_query(query, ids) do
    from(
      entity in query,
      where: entity.id in ^ids,
      order_by: fragment("array_position(?, ?::int)", ^ids, entity.id)
    )
  end
end
