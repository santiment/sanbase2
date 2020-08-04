defmodule SanbaseWeb.Graphql.Schema.WatchlistQueries do
  @moduledoc ~s"""
  Queries and mutations for working with watchlists (lists of projects)

  A watchlist is defined as a concrete list of project slugs or a function that
  dynamically determines what projects are in it.
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.WatchlistResolver

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :watchlist_queries do
    @desc "Fetch all watchlists for the current user"
    field :fetch_watchlists, list_of(:user_list) do
      meta(access: :free)

      resolve(&WatchlistResolver.fetch_user_lists/3)
    end

    @desc "Fetch all public watchlists for current_user."
    field :fetch_public_watchlists, list_of(:user_list) do
      meta(access: :free)

      resolve(&WatchlistResolver.fetch_public_user_lists/3)
    end

    @desc "Fetch all public watchlists"
    field :fetch_all_public_watchlists, list_of(:user_list) do
      meta(access: :free)

      resolve(&WatchlistResolver.fetch_all_public_user_lists/3)
    end

    @desc ~s"""
    Return a watchlist. All public watchlists are accessible to anyone. Private
    watchlists are accessible only by their owner.
    """
    field :watchlist, :user_list do
      meta(access: :free)

      arg(:id, non_null(:id))
      resolve(&WatchlistResolver.watchlist/3)
    end

    field :watchlist_by_slug, :user_list do
      meta(access: :free)

      arg(:slug, non_null(:string))
      resolve(&WatchlistResolver.watchlist_by_slug/3)
    end
  end

  object :watchlist_mutations do
    @desc """
    Create a watchlist.
    """
    field :create_watchlist, :user_list do
      arg(:name, non_null(:string))
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)
      arg(:table_configuration_id, :integer)

      middleware(JWTAuth)
      resolve(&WatchlistResolver.create_user_list/3)
    end

    @desc """
    Update user favourites list.
    """
    field :update_user_list, :user_list do
      deprecate("Use `updateWatchlist` instead")
      arg(:id, non_null(:integer))
      arg(:name, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)
      arg(:list_items, list_of(:input_list_item))
      arg(:is_monitored, :boolean)

      middleware(JWTAuth)
      resolve(&WatchlistResolver.update_user_list/3)
    end

    @desc """
    Update a watchlist
    """
    field :update_watchlist, :user_list do
      arg(:id, non_null(:integer))
      arg(:name, :string)
      arg(:description, :string)
      arg(:is_public, :boolean)
      arg(:color, :color_enum)
      arg(:function, :json)
      arg(:list_items, list_of(:input_list_item))
      arg(:is_monitored, :boolean)
      arg(:table_configuration_id, :integer)

      middleware(JWTAuth)
      resolve(&WatchlistResolver.update_user_list/3)
    end

    field :update_watchlist_settings, :watchlist_settings do
      arg(:id, non_null(:integer))
      arg(:settings, non_null(:watchlist_settings_input_object))

      middleware(JWTAuth)
      resolve(&WatchlistResolver.update_watchlist_settings/3)
    end

    @desc "Remove user favourites list."
    field :remove_user_list, :user_list do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&WatchlistResolver.remove_user_list/3)
    end

    @desc "Remove a watchlist."
    field :remove_watchlist, :user_list do
      arg(:id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&WatchlistResolver.remove_user_list/3)
    end
  end
end
