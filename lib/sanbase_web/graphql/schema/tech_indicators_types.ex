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

  object :social_volume do
    field(:datetime, non_null(:datetime))
    field(:mentions_count, :integer)
  end

  enum :social_volume_type do
    value(:professional_traders_chat_overview)
    value(:telegram_chats_overview)
    value(:telegram_discussion_overview)
  end
end
