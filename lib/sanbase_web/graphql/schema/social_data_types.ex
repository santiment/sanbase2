defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  enum :trending_words_sources do
    value(:telegram)
    value(:professional_traders_chat)
    value(:reddit)
    value(:all)
  end

  enum :social_gainers_losers_status do
    value(:gainer)
    value(:loser)
    value(:newcomer)
    value(:all)
  end

  object :trending_words do
    field(:datetime, non_null(:datetime))
    field(:top_words, list_of(:word_with_context))
  end

  object :word_with_context do
    field :context, list_of(:word_context) do
      cache_resolve(&SocialDataResolver.word_context/3)
    end

    field(:score, :float)
    field(:word, :string)
  end

  object :word_trend_score do
    field(:datetime, non_null(:datetime))
    field(:score, non_null(:float))
    field(:source, :trending_words_sources)
  end

  object :word_context do
    field(:word, non_null(:string))
    field(:score, non_null(:float))
  end

  object :top_social_gainers_losers do
    field(:datetime, non_null(:datetime))
    field(:projects, list_of(:projects_change))
  end

  object :projects_change do
    field(:project, non_null(:string))
    field(:change, non_null(:float))
    field(:status, :social_gainers_losers_status)
  end
end
