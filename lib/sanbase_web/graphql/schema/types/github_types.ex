defmodule SanbaseWeb.Graphql.GithubTypes do
  use Absinthe.Schema.Notation

  enum :github_activity_stats_sort_by do
    value(:dev_activity)
    value(:github_activity)
  end

  @desc ~s"""
  Select the projects for which to fetch github activity stats.

  Exactly one of `slugs` and `topN` must be provided:
    - `slugs` - Fetch the stats for the given list of slugs. `sortBy` is
      optional and controls the order of the result. Without it the result
      is in the same order as the input slugs.
    - `topN` - Fetch the stats for the top N projects, ranked by the `sortBy`
      stat in the given time period. `sortBy` is required.
  """
  input_object :github_activity_stats_selector_input_object do
    field(:slugs, list_of(non_null(:string)))
    field(:top_n, :integer)
    field(:sort_by, :github_activity_stats_sort_by)
  end

  object :github_activity_stats do
    field(:slug, non_null(:string))
    field(:dev_activity, non_null(:integer))
    field(:github_activity, non_null(:integer))
    field(:dev_activity_contributors_count, non_null(:integer))
    field(:github_activity_contributors_count, non_null(:integer))
    field(:bot_dev_activity, non_null(:integer))
    field(:bot_github_activity, non_null(:integer))
    field(:bot_contributors_count, non_null(:integer))
  end
end
