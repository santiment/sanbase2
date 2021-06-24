defmodule SanbaseWeb.Graphql.Schema.DiscordQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.DiscordResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :discord_mutations do
    @desc ~s"""
    Add User to Pro role in our discord server
    """
    field :add_to_pro_role_in_discord, :boolean do
      arg(:discord_username, non_null(:string))

      middleware(JWTAuth)

      resolve(&DiscordResolver.add_to_pro_role_in_discord/3)
    end
  end
end
