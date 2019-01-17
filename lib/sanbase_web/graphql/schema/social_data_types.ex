defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver

  object :trending_words do
    field(:datetime, non_null(:datetime))
    field(:top_words, list_of(:word_with_context))
  end

  object :word_score do
    field(:word, :string)
    field(:score, :float)
  end

  object :word_with_context do
    field :context, list_of(:word_context) do
      resolve(&SocialDataResolver.word_context/3)
    end

    field(:score, :float)
    field(:word, :string)
  end

  enum :trending_words_sources do
    value(:telegram)
    value(:professional_traders_chat)
    value(:reddit)
    value(:all)
  end

  object :word_context do
    field(:word, non_null(:string))
    field(:score, non_null(:float))
  end
end
