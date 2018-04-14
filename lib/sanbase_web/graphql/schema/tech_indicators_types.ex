defmodule SanbaseWeb.Graphql.TechIndicatorsTypes do
  use Absinthe.Schema.Notation

  object :macd do
    field(:datetime, non_null(:datetime))
    field(:macd, :float)
  end

  object :rsi do
    field(:datetime, non_null(:datetime))
    field(:rsi, :float)
  end

  object :price_volume_diff do
    field(:datetime, non_null(:datetime))
    field(:price_volume_diff, :float)
    field(:price_change, :float)
    field(:volume_change, :float)
  end

  object :twitter_mention_count do
    field(:datetime, non_null(:datetime))
    field(:mention_count, :integer)
  end

  object :emojis_sentiment do
    field(:datetime, non_null(:datetime))
    field(:sentiment, :float)
  end
end
