defmodule SanbaseWeb.Graphql.TechIndicatorsTypes do
  use Absinthe.Schema.Notation

  object :macd do
    field(:datetime, non_null(:datetime))
    field(:macd, :decimal)
  end

  object :rsi do
    field(:datetime, non_null(:datetime))
    field(:rsi, :decimal)
  end

  object :price_volume_diff do
    field(:datetime, non_null(:datetime))
    field(:price_volume_diff, :decimal)
    field(:price_change, :decimal)
    field(:volume_change, :decimal)
  end

  object :twitter_mention_count do
    field(:datetime, non_null(:datetime))
    field(:mention_count, :decimal)
  end
end
