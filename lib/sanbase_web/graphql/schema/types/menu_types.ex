defmodule SanbaseWeb.Graphql.MenuTypes do
  use Absinthe.Schema.Notation

  @desc ~s"""
  A menu item is defined by the id of an existing entity.
  Exactly one of the entities must be set.
  """
  input_object :menu_item_entity do
    field(:query_id, :integer)
    field(:dashboard_id, :integer)
    field(:menu_id, :integer)
  end
end
