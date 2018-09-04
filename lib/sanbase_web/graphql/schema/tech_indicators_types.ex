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

  object :erc20_exchange_funds_flow do
    field(:ticker, :string)
    field(:contract, :string)
    field(:exchange_in, :float)
    field(:exchange_out, :float)
    field(:exchange_diff, :float)
    field(:exchange_in_usd, :float)
    field(:exchange_out_usd, :float)
    field(:exchange_diff_usd, :float)
    field(:percent_diff_exchange_diff_usd, :float)
    field(:exchange_volume_usd, :float)
    field(:percent_diff_exchange_volume_usd, :float)
    field(:exchange_in_btc, :float)
    field(:exchange_out_btc, :float)
    field(:exchange_diff_btc, :float)
    field(:percent_diff_exchange_diff_btc, :float)
    field(:exchange_volume_btc, :float)
    field(:percent_diff_exchange_volume_btc, :float)
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

  enum :topic_search_sources do
    value(:telegram)
    value(:professional_traders_chat)
    value(:reddit)
  end

  object :topic_search do
    field(:messages, list_of(:messages))
    field(:chart_data, list_of(:chart_data))
  end

  object :topic_search_overview do
    field(:messages, list_of(:topic_search_messages))
    field(:chart_data, list_of(:topic_search_chart_data))
  end

  object :messages do
    field(:text, :string)
    field(:datetime, non_null(:datetime))
  end

  object :chart_data do
    field(:mentions_count, :integer)
    field(:datetime, non_null(:datetime))
  end

  object :twitter_mention_count do
    field(:datetime, non_null(:datetime))
    field(:mention_count, :integer)
  end
end
