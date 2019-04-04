defmodule SanbaseWeb.Graphql.Schema.SocialDataQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.TechIndicators
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
      * socialVolumeType - the source of mention counts, one of the following:
        1. "PROFESSIONAL_TRADERS_CHAT_OVERVIEW" - shows how many times the given project has been mentioned in the professional traders chat
        2. "TELEGRAM_CHATS_OVERVIEW" - shows how many times the given project has been mentioned across all telegram chats, except the project's own community chat (if there is one)
        3. "TELEGRAM_DISCUSSION_OVERVIEW" - the general volume of messages in the project's community chat (if there is one)
        4. "DISCORD_DISCUSSION_OVERVIEW" - shows how many times the given project has been mentioned in the discord channels
    """
    field :social_dominance, list_of(:social_dominance) do
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, non_null(:string), default_value: "1d")
      arg(:social_volume_type, non_null(:social_volume_type))

      complexity(&Complexity.from_to_interval/3)
      middleware(ApiTimeframeRestriction)
      resolve(&TechIndicatorsResolver.social_dominance/3)
    end
  end
end