defmodule SanbaseWeb.Graphql.Kafka.SubscriptionTest do
  use SanbaseWeb.SubscriptionCase

  alias Sanbase.Kafka.Subscription
  alias Sanbase.Kafka.Topic.{ExchangeTrade, ExchangeMarketDepth}

  @exchange_trades_sub """
  subscription($exchange: String!, $tickerPair: String) {
    exchangeTrades(exchange: $exchange, tickerPair: $tickerPair) {
      exchange
      tickerPair
      datetime
      amount
      price
      cost
    }
  }
  """

  @exchange_market_depth_sub """
  subscription($exchange: String!, $tickerPair: String) {
    exchangeMarketDepth(exchange: $exchange, tickerPair: $tickerPair) {
      exchange
      tickerPair
      datetime
      ask
      bid
      asks025PercentDepth
      asks025PercentVolume
      bids025PercentDepth
      bids025PercentVolume
    }
  }
  """

  @exchange_trade_example %{
    "amount" => 2.11604737,
    "cost" => 337.7846416731,
    "price" => 159.63,
    "side" => "buy",
    "source" => "Kraken",
    "symbol" => "ETH/EUR",
    "timestamp" => 1_569_704_025_915
  }

  @exchange_market_depth_example %{
    "source" => "Kraken",
    "bids_1_percent_depth" => 6.377517025310313,
    "bids_30_percent_volume" => nil,
    "bids_30_percent_depth" => nil,
    "asks_0_75_percent_volume" => 323.69397143000003,
    "asks_0_75_percent_depth" => 1.4837395268415359,
    "asks_30_percent_depth" => nil,
    "asks_2_percent_depth" => 4.350476783883327,
    "bid" => 0.00455005,
    "asks_5_percent_volume" => 1028.7124032100003,
    "bids_10_percent_volume" => 1898.7281255600003,
    "asks_30_percent_volume" => nil,
    "bids_10_percent_depth" => 8.53569299297473,
    "bids_0_25_percent_volume" => 173.00153222999998,
    "asks_10_percent_volume" => nil,
    "asks_5_percent_depth" => 4.738938267011328,
    "asks_1_percent_depth" => 4.035078675155194,
    "timestamp" => 1_571_417_428_152,
    "asks_10_percent_depth" => nil,
    "bids_0_25_percent_depth" => 0.7868672411467281,
    "asks_1_percent_volume" => 878.31510571,
    "bids_1_percent_volume" => 1410.8348067900001,
    "bids_5_percent_volume" => 1772.2867537800003,
    "ask" => 0.00455979,
    "bids_0_75_percent_depth" => 3.113377417399543,
    "bids_5_percent_depth" => 7.995039456119882,
    "bids_0_5_percent_depth" => 3.0702330535995435,
    "bids_0_75_percent_volume" => 686.67829275,
    "asks_2_percent_volume" => 946.56222608,
    "asks_0_5_percent_volume" => 39.858584230000005,
    "asks_0_25_percent_volume" => 0.28495291,
    "asks_20_percent_volume" => nil,
    "bids_2_percent_volume" => 1719.6704601100002,
    "asks_20_percent_depth" => nil,
    "symbol" => "ZEC/BTC",
    "bids_0_5_percent_volume" => 677.13829275,
    "asks_0_5_percent_depth" => 0.1823476153675852,
    "bids_2_percent_depth" => 7.762576530692765,
    "asks_0_25_percent_depth" => 0.0012996121796948,
    "bids_20_percent_volume" => nil,
    "bids_20_percent_depth" => nil
  }

  describe "exchange_trades" do
    test "subscribe to given exchange - receive only those", %{socket: socket} do
      ref = push_doc(socket, @exchange_trades_sub, variables: %{"exchange" => "Kraken"})
      assert_reply(ref, :ok, %{subscriptionId: subscription_id})

      message = ExchangeTrade.format_message(@exchange_trade_example)
      Subscription.publish(message, "exchange_trades")

      expected = expected_exchange_trade(subscription_id)
      assert_push("subscription:data", push)
      assert expected == push
    end

    test "subscribe to given exchange - doesn't receive other exchanges", %{socket: socket} do
      ref = push_doc(socket, @exchange_trades_sub, variables: %{"exchange" => "Poloniex"})
      assert_reply(ref, :ok, %{subscriptionId: _subscription_id})

      message = ExchangeTrade.format_message(@exchange_trade_example)

      Subscription.publish(message, "exchange_trades")

      refute_push("subscription:data", _push)
    end

    test "subscribe to exchange and ticker_pair - receive only those", %{socket: socket} do
      ref =
        push_doc(socket, @exchange_trades_sub,
          variables: %{"exchange" => "Kraken", "tickerPair" => "ETH/EUR"}
        )

      assert_reply(ref, :ok, %{subscriptionId: subscription_id})

      message = ExchangeTrade.format_message(@exchange_trade_example)

      Subscription.publish(message, "exchange_trades")

      expected = expected_exchange_trade(subscription_id)
      assert_push("subscription:data", push)
      assert expected == push
    end

    test "subscribe to exchange and ticker_pair - doesn't receive for other symbols", %{
      socket: socket
    } do
      ref =
        push_doc(socket, @exchange_trades_sub,
          variables: %{"exchange" => "Kraken", "tickerPair" => "ETH/USDT"}
        )

      assert_reply(ref, :ok, %{subscriptionId: _subscription_id})

      message = ExchangeTrade.format_message(@exchange_trade_example)

      Subscription.publish(message, "exchange_trades")

      refute_push("subscription:data", _push)
    end
  end

  describe "exchange_market_depth" do
    test "subscribe to given exchange - receive only those", %{socket: socket} do
      ref = push_doc(socket, @exchange_market_depth_sub, variables: %{"exchange" => "Kraken"})
      assert_reply(ref, :ok, %{subscriptionId: subscription_id})

      message = ExchangeMarketDepth.format_message(@exchange_market_depth_example)
      Subscription.publish(message, "exchange_market_depth")

      expected = expected_exchange_market_depth(subscription_id)
      assert_push("subscription:data", push)
      assert expected == push
    end

    test "subscribe to given exchange - doesn't receive other sources", %{socket: socket} do
      ref = push_doc(socket, @exchange_market_depth_sub, variables: %{"exchange" => "Poloniex"})
      assert_reply(ref, :ok, %{subscriptionId: _subscription_id})

      message = ExchangeMarketDepth.format_message(@exchange_market_depth_example)
      Subscription.publish(message, "exchange_market_depth")

      refute_push("subscription:data", _push)
    end

    test "subscribe to exchange and tickerPair - receive only those", %{socket: socket} do
      ref =
        push_doc(socket, @exchange_market_depth_sub,
          variables: %{"exchange" => "Kraken", "tickerPair" => "ZEC/BTC"}
        )

      assert_reply(ref, :ok, %{subscriptionId: subscription_id})

      message = ExchangeMarketDepth.format_message(@exchange_market_depth_example)
      Subscription.publish(message, "exchange_market_depth")

      expected = expected_exchange_market_depth(subscription_id)
      assert_push("subscription:data", push)
      assert expected == push
    end

    test "subscribe to exchange and tickerPair - doesn't receive for other symbols", %{
      socket: socket
    } do
      ref =
        push_doc(socket, @exchange_market_depth_sub,
          variables: %{"exchange" => "Kraken", "tickerPair" => "ETH/USDT"}
        )

      assert_reply(ref, :ok, %{subscriptionId: _subscription_id})

      message = ExchangeMarketDepth.format_message(@exchange_market_depth_example)
      Subscription.publish(message, "exchange_market_depth")

      refute_push("subscription:data", _push)
    end
  end

  defp expected_exchange_trade(subscription_id) do
    %{
      result: %{
        data: %{
          "exchangeTrades" => %{
            "amount" => 2.11604737,
            "cost" => 337.7846416731,
            "price" => 159.63,
            "exchange" => "Kraken",
            "tickerPair" => "ETH/EUR",
            "datetime" => "2019-09-28T20:53:45Z"
          }
        }
      },
      subscriptionId: subscription_id
    }
  end

  defp expected_exchange_market_depth(subscription_id) do
    %{
      result: %{
        data: %{
          "exchangeMarketDepth" => %{
            "ask" => 0.00455979,
            "asks025PercentDepth" => 0.0012996121796948,
            "asks025PercentVolume" => 0.28495291,
            "bid" => 0.00455005,
            "bids025PercentDepth" => 0.7868672411467281,
            "bids025PercentVolume" => 173.00153222999998,
            "exchange" => "Kraken",
            "tickerPair" => "ZEC/BTC",
            "datetime" => "2019-10-18T16:50:28Z"
          }
        }
      },
      subscriptionId: subscription_id
    }
  end
end
