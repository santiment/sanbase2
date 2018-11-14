defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  object :trending_words do
    field(:datetime, non_null(:datetime))
    field(:top_words, list_of(:words))
  end

  object :words do
    field(:word, :string)
    field(:score, :float)
  end
end
