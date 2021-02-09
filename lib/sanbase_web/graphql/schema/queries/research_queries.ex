defmodule SanbaseWeb.Graphql.Schema.ResearchQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.ResearchResolver

  object :research_queries do
    field :uniswap_value_distribution, :uniswap_value_distribution do
      cache_resolve(&ResearchResolver.uniswap_value_distribution/3)
    end

    field :uniswap_who_claimed, :uniswap_who_claimed do
      cache_resolve(&ResearchResolver.uniswap_who_claimed/3)
    end
  end
end
