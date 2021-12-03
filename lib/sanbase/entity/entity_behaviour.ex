defmodule Sanbase.Entity.Behaviour do
  @type entity :: map()
  @type id :: integer() | binary()
  @type ids :: list(id) | list(ids)
  @type error :: binary()
  @type opts :: Keyword.t()

  @callback by_id!(id, opts) :: entity | no_return
  @callback by_id(id, opts) :: {:ok, entity} | {:error, error}
  @callback by_ids(ids, opts) :: {:ok, list(entity)} | {:error, error}
  @callback by_ids!(ids, opts) :: list(entity) | no_return

  @callback public_entity_ids_query(opts) :: Ecto.Query.t()
end
