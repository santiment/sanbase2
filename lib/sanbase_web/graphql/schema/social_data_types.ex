defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  object :trending_words do
    field(:datetime, non_null(:datetime))
    field(:top_words, list_of(:word_score))
  end

  object :word_score do
    field(:word, :string)
    field(:score, :float)
  end

  enum :trending_words_sources do
    value(:telegram)
    value(:professional_traders_chat)
    value(:reddit)
    value(:all)
  end

  object :word_context do
    field(:word, non_null(:string))
    field(:size, non_null(:float))
  end
end
