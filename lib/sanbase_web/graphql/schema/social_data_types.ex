defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  enum :trending_words_sources do
    value(:telegram)
    value(:professional_traders_chat)
    value(:reddit)
    value(:all)
  end

  enum :social_dominance_sources do
    value(:telegram)
    value(:professional_traders_chat)
    value(:reddit)
    value(:discord)
    value(:all)
  end

  enum :social_gainers_losers_status_enum do
    value(:gainer)
    value(:loser)
    value(:newcomer)
    value(:all)
  end

  enum :social_volume_type do
    value(:professional_traders_chat_overview)
    value(:telegram_chats_overview)
    value(:telegram_discussion_overview)
    value(:discord_discussion_overview)
  end

  object :social_volume do
    field(:datetime, non_null(:datetime))
    field(:mentions_count, :integer)
  end

  object :social_dominance do
    field(:datetime, non_null(:datetime))
    field(:dominance, :float)
  end

  object :news do
    field(:datetime, non_null(:datetime))
    field(:title, :string)
    field(:description, :string)
    field(:url, :string)
    field(:media_url, :string)
    field(:source_name, :string)
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
    field(:slug, non_null(:string))
    field(:change, non_null(:float))
    field(:status, :social_gainers_losers_status_enum)
  end

  object :social_gainers_losers_status do
    field(:datetime, non_null(:datetime))
    field(:change, non_null(:float))
    field(:status, :social_gainers_losers_status_enum)
  end
end
