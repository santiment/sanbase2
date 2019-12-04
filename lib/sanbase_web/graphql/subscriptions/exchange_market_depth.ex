defmodule SanbaseWeb.Graphql.Subscriptions.ExchangeMarketDepth do
  @behaviour SanbaseWeb.Graphql.Subscription

  def publish(message) do
    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      exchange_market_depth: message.exchange <> message.ticker_pair
    )

    Absinthe.Subscription.publish(SanbaseWeb.Endpoint, message,
      exchange_market_depth: message.exchange
    )
  end
end
