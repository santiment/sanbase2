defmodule SanbaseWeb.Graphql.Subscriptions.ExchangeMarketDepth do
  @behaviour SanbaseWeb.Graphql.Subscription

  def publish(message) do
    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      exchange_market_depth: message.source <> message.symbol
    )

    Absinthe.Subscription.publish(SanbaseWeb.Endpoint, message,
      exchange_market_depth: message.source
    )
  end
end
