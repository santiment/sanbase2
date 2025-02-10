defmodule SanbaseWeb.Graphql.Schema.MenuQueries do
  @moduledoc ~s"""
  Queries and mutations for working with short urls
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Resolvers.MenuResolver

  object :menu_queries do
    field :get_menu, :json do
      meta(access: :free)
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&MenuResolver.get_menu/3)
    end
  end

  object :menu_mutations do
    field :create_menu, :json do
      arg(:name, non_null(:string))
      arg(:description, :string)

      @desc ~s"""
      If the menu is a sub-menu, this field should be set to the parent menu's id.
      If this field is not set or explicitly set to null, the menu will be created as
      a top-level menu
      """
      arg(:parent_id, :integer, default_value: nil)

      @desc ~s"""
      If :parent_id is provided, position is used to determine the position of the menu
      is the parent menu. If not provided, it will be appended to the end of the list.
      If a position is provided, all menu items with the same or bigger position in the same
      menu will get their position increased by 1 in order to accomodate the new menu item.
      """
      arg(:position, :integer, default_value: nil)

      middleware(JWTAuth)

      resolve(&MenuResolver.create_menu/3)
    end

    field :update_menu, :json do
      arg(:id, non_null(:integer))

      arg(:name, :string)
      arg(:description, :string)
      arg(:parent_id, :integer)

      middleware(JWTAuth)

      resolve(&MenuResolver.update_menu/3)
    end

    field :delete_menu, :json do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&MenuResolver.delete_menu/3)
    end

    field :create_menu_item, :json do
      arg(:parent_id, non_null(:integer))
      arg(:entity, non_null(:menu_item_entity))
      arg(:position, :integer)

      middleware(JWTAuth)

      resolve(&MenuResolver.create_menu_item/3)
    end

    field :update_menu_item, :json do
      arg(:id, non_null(:integer))
      arg(:position, :integer)
      arg(:parent_id, :integer)

      middleware(JWTAuth)

      resolve(&MenuResolver.update_menu_item/3)
    end

    field :delete_menu_item, :json do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&MenuResolver.delete_menu_item/3)
    end
  end
end
