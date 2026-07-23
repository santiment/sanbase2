defmodule SanbaseWeb.Graphql.Schema.GithubQueries do
  @moduledoc ~s"""
  Queries for github activity data
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.GithubResolver

  object :github_queries do
    @desc ~s"""
    Aggregated github activity stats for a list of projects in a given
    time period. Returns one entry per requested slug with the total
    dev/github activity and contributors count, as well as the same
    numbers computed only for bot accounts.

    Projects without github organizations or without any activity in the
    time period are returned with zero values.
    """
    field :github_activity_stats, list_of(:github_activity_stats) do
      meta(access: :free)

      arg(:slugs, non_null(list_of(non_null(:string))))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&GithubResolver.github_activity_stats/3, ttl: 300)
    end
  end
end
