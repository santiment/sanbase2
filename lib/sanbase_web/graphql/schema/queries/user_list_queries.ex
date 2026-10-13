defmodule SanbaseWeb.Graphql.Schema.UserListQueries do
  @moduledoc ~s"""
  Queries and mutations for working with watchlists (lists of projects)

  A watchlist is defined as a concrete list of project slugs or a function that
  dynamically determines what projects are in it.
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.UserListResolver

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :user_list_queries do
    @desc "Fetch all watchlists for the current user"
    field :fetch_watchlists, list_of(:user_list) do
      meta(access: :free)
      arg(:type, :watchlist_type_enum, default_value: :project)

      resolve(&UserListResolver.fetch_user_lists/3)
    end

    @desc "Fetch all public watchlists for current_user."
    field :fetch_public_watchlists, list_of(:user_list) do
      meta(access: :free)
      arg(:type, :watchlist_type_enum, default_value: :project)

      resolve(&UserListResolver.fetch_public_user_lists/3)
    end

    @desc "Fetch all public watchlists"
    field :fetch_all_public_watchlists, list_of(:user_list) do
      meta(access: :free)

      arg(:type, :watchlist_type_enum, default_value: :project)

      resolve(&UserListResolver.fetch_all_public_user_lists/3)
    end

    # field :dynamic_watchlist, :user_list do
    #   meta(access: :free)

    #   arg(:projects_selector, :projects_selector_input_object)
    #   arg(:blockchain_addresses_selector, :blockchain_addresses_selector_input_object)

    #   resolve(&UserListResolver.dynamic_watchlist/3)
    # end

    field :watchlist, :user_list do
      meta(access: :free)

      arg(:id, non_null(:id))

      resolve(&UserListResolver.watchlist/3)
    end

    field :watchlist_by_slug, :user_list do
      meta(access: :free)

      arg(:slug, non_null(:string))
      arg(:selector, :projects_selector_input_object)

      resolve(&UserListResolver.watchlist_by_slug/3)
    end
  end

  object :user_list_mutations do
    @desc """
    Create a watchlist.
    """
    field :create_watchlist, :user_list do
      arg(:name, non_null(:string))
      arg(:type, :watchlist_type_enum, default_value: :project)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)
      arg(:table_configuration_id, :integer)
      arg(:list_items, list_of(:input_list_item))
      arg(:is_screener, :boolean)

      middleware(JWTAuth)
      resolve(&UserListResolver.create_user_list/3)
    end

    @desc """
    Update a watchlist
    """
    field :update_watchlist, :user_list do
      arg(:id, non_null(:integer))
      arg(:name, :string)
      arg(:type, :watchlist_type_enum)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)
      arg(:list_items, list_of(:input_list_item))
      arg(:is_monitored, :boolean)
      arg(:table_configuration_id, :integer)
      arg(:is_screener, :boolean)

      middleware(JWTAuth)
      resolve(&UserListResolver.update_watchlist/3)
    end

    field :add_watchlist_items, :user_list do
      arg(:id, non_null(:integer))
      arg(:list_items, non_null(list_of(:input_list_item)))

      middleware(JWTAuth)
      resolve(&UserListResolver.add_watchlist_items/3)
    end

    field :remove_watchlist_items, :user_list do
      arg(:id, non_null(:integer))
      arg(:list_items, non_null(list_of(:input_list_item)))

      middleware(JWTAuth)
      resolve(&UserListResolver.remove_watchlist_items/3)
    end

    field :update_watchlist_settings, :watchlist_settings do
      arg(:id, non_null(:integer))
      arg(:settings, non_null(:watchlist_settings_input_object))

      middleware(JWTAuth)
      resolve(&UserListResolver.update_watchlist_settings/3)
    end

    @desc "Remove user favourites list."
    field :remove_user_list, :user_list do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&UserListResolver.remove_user_list/3)
    end

    @desc "Remove a watchlist."
    field :remove_watchlist, :user_list do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&UserListResolver.remove_user_list/3)
    end
  end
end
