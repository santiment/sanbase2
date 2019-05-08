defmodule SanbaseWeb.Graphql.Schema.WatchlistQueries do
  @moduledoc ~s"""
  Queries and mutations for working with watchlists (lists of projects)

  A watchlist is defined as a concrete list of project slugs or a function that
  dynamically determines what projects are in it.
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.{
    WatchlistResolver,
    UserListResolver
  }

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :user_list_queries do
    @desc "Fetch all favourites lists for current_user."
    field :fetch_user_lists, list_of(:user_list) do
      resolve(&UserListResolver.fetch_user_lists/3)
    end

    @desc "Fetch all public favourites lists for current_user."
    field :fetch_public_user_lists, list_of(:user_list) do
      resolve(&UserListResolver.fetch_public_user_lists/3)
    end

    @desc "Fetch all public favourites lists"
    field :fetch_all_public_user_lists, list_of(:user_list) do
      resolve(&UserListResolver.fetch_all_public_user_lists/3)
    end

    @desc ~s"""
    Fetch public favourites list by list id.
    If the list is owned by the current user then the list can be private as well.
    This query returns either a single user list item or null.
    """
    field :user_list, :user_list do
      arg(:user_list_id, non_null(:id))

      cache_resolve(&UserListResolver.user_list/3)
    end
  end

  object :user_list_mutations do
    @desc """
    Create user favourites list.
    """
    field :create_user_list, :user_list do
      arg(:name, non_null(:string))
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)

      middleware(JWTAuth)
      resolve(&UserListResolver.create_user_list/3)
    end

    @desc """
    Update user favourites list.
    """
    field :update_user_list, :user_list do
      arg(:id, non_null(:integer))
      arg(:name, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)
      arg(:list_items, list_of(:input_list_item))

      middleware(JWTAuth)
      resolve(&UserListResolver.update_user_list/3)
    end

    @desc "Remove user favourites list."
    field :remove_user_list, :user_list do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&UserListResolver.remove_user_list/3)
    end
  end
end
