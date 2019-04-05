defmodule SanbaseWeb.Graphql.Schema.SocialDataQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver
  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.ApiTimeframeRestriction

  import_types(SanbaseWeb.Graphql.SocialDataTypes)

  object :social_data_queries do
    @desc ~s"""
    Returns the % of the social dominance a given project has over time in a given social channel.

    Arguments description:
      * slug - a string uniquely identifying a project
      * interval - an integer followed by one of: `m`, `h`, `d`, `w`
      * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
      * source - the source of mention counts, one of the following:
        1. "PROFESSIONAL_TRADERS_CHAT" - shows the relative social dominance of this project on the web chats where trades talk
        2. "TELEGRAM" - shows the relative social dominance of this project in the telegram crypto channels
        3. "DISCORD" - shows the relative social dominance of this project on discord crypto communities
        4. "REDDIT" - shows the relative social dominance of this project on crypto subreddits
    """
    field :social_dominance, list_of(:social_dominance) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")
      arg(:source, non_null(:social_dominance_sources))

      complexity(&Complexity.from_to_interval/3)
      middleware(ApiTimeframeRestriction)
      resolve(&SocialDataResolver.social_dominance/3)
    end
  end
end