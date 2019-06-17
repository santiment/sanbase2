defmodule SanbaseWeb.Graphql.Schema.FeaturedQueries do
  @moduledoc ~s"""
  Queries and mutations for working with featured insights, watchlists
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.FeaturedItemResolver

  object :featured_queries do
    field :featured_insights, list_of(:post) do
      cache_resolve(&FeaturedItemResolver.insights/3)
    end

    field :featured_watchlists, list_of(:user_list) do
      cache_resolve(&FeaturedItemResolver.watchlists/3)
    end

    field :featured_user_triggers, list_of(:user_trigger) do
      cache_resolve(&FeaturedItemResolver.user_triggers/3)
    end
  end
end
