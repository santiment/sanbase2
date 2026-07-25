defmodule SanbaseWeb.Graphql.Schema.GithubQueries do
  @moduledoc ~s"""
  Queries for github activity data
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.GithubResolver

  object :github_queries do
    @desc ~s"""
    Aggregated github activity stats for a list of projects in a given time
    period. Returns one entry per project with the total dev/github activity
    and contributors count, as well as the same numbers computed only for bot
    accounts - actors whose name ends with `[bot]`. The bot numbers are a
    subset of the totals, they are not subtracted from them.

    The projects are selected either explicitly, by providing a list of slugs,
    or dynamically, by providing topN and sortBy, which returns the top N
    projects ranked by the given stat in the time period.

    When slugs are provided, projects without github organizations or without
    any activity in the time period are returned with zero values.
    """
    field :github_activity_stats, list_of(:github_activity_stats) do
      meta(access: :free)

      arg(:selector, non_null(:github_activity_stats_selector_input_object))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      cache_resolve(&GithubResolver.github_activity_stats/3, ttl: 300)
    end
  end
end
