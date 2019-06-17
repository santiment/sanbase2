defmodule SanbaseWeb.Graphql.Schema.GithubQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.GithubResolver
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.TimeframeRestriction

  import_types(SanbaseWeb.Graphql.GithubTypes)

  object :github_queries do
    @desc "Returns a list of slugs of the projects that have a github link"
    field :github_availables_repos, list_of(:string) do
      cache_resolve(&GithubResolver.available_repos/3)
    end

    @desc ~s"""
    Returns a list of github activity for a given slug and time interval.

    Arguments description:
      * interval - an integer followed by one of: `s`, `m`, `h`, `d` or `w`
      * transform - one of the following:
        1. None (default)
        2. movingAverage
      * movingAverageIntervalBase - used only if transform is `movingAverage`.
        An integer followed by one of: `s`, `m`, `h`, `d` or `w`, representing time units.
        It is used to calculate the moving avarage interval.
    """
    field :github_activity, list_of(:activity_point) do
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")
      arg(:transform, :string, default_value: "None")
      arg(:moving_average_interval_base, :integer, default_value: 7)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true})
      cache_resolve(&GithubResolver.github_activity/3)
    end

    @desc ~s"""
    Gets the pure dev activity of a project. Pure dev activity is the number of all events
    excluding Comments, Issues and PR Comments
    """
    field :dev_activity, list_of(:activity_point) do
      arg(:slug, :string)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string))
      arg(:transform, :string, default_value: "None")
      arg(:moving_average_interval_base, :integer, default_value: 7)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction, %{allow_historical_data: true})
      cache_resolve(&GithubResolver.dev_activity/3, ttl: 600, max_ttl_offset: 600)
    end
  end
end
