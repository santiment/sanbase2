defmodule SanbaseWeb.Graphql.Subscriptions.ExchangeTrades do
  @behaviour SanbaseWeb.Graphql.Subscription

  def publish(message) do
    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      exchange_trades: message.source <> message.symbol
    )

    Absinthe.Subscription.publish(SanbaseWeb.Endpoint, message, exchange_trades: message.source)
  end
end
