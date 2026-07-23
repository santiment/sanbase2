defmodule SanbaseWeb.Graphql.GithubTypes do
  use Absinthe.Schema.Notation

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
