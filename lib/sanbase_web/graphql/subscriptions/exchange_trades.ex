defmodule SanbaseWeb.Graphql.Subscriptions.ExchangeTrades do
  @behaviour SanbaseWeb.Graphql.Subscription

  def publish(message) do
    Absinthe.Subscription.publish(
      SanbaseWeb.Endpoint,
      message,
      exchange_trades: message.exchange <> message.ticker_pair
    )

    Absinthe.Subscription.publish(SanbaseWeb.Endpoint, message, exchange_trades: message.exchange)
  end
end
