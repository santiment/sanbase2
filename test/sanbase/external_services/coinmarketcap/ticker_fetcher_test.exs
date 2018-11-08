defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcherTest do
  use ExUnit.Case
  use Sanbase.DataCase, async: false

  # TODO: Change after old cmc scraper is removed
  alias Sanbase.ExternalServices.Coinmarketcap.TickerFetcher2, as: TickerFetcher
  alias Sanbase.Prices.Store

  @btc_measurement "BTC_bitcoin"
  @eth_measurement "ETH_ethereum"
  @xrp_measurement "XRP_ripple"
  @bch_measurement "BCH_bitcoin-cash"
  @eos_measurement "EOS_eos"

  test "parsing the project page", _context do
    Store.create_db()

    Tesla.Mock.mock(fn %{method: :get} ->
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "v2_ticker_5.json"))}
    end)

    Store.drop_measurement(@btc_measurement)
    Store.drop_measurement(@eth_measurement)
    Store.drop_measurement(@xrp_measurement)
    Store.drop_measurement(@bch_measurement)
    Store.drop_measurement(@eos_measurement)

    TickerFetcher.work()

    from = DateTime.from_naive!(~N[2018-11-08 10:35:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2018-11-08 10:40:00], "Etc/UTC")

    # Test bitcoin is in influx
    assert Store.fetch_price_points!(@btc_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-11-08 10:38:15], "Etc/UTC"),
               6481.63850144,
               1,
               112_558_027_683,
               4_545_288_572
             ]
           ]

    # Test Ethereum is in influx
    assert Store.fetch_price_points!(@eth_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-11-08 10:38:44], "Etc/UTC"),
               214.428922185,
               0.033082518,
               22_101_582_138,
               1_642_522_945
             ]
           ]

    # Test Ripple is in influx
    assert Store.fetch_price_points!(@xrp_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-11-08 10:38:06], "Etc/UTC"),
               0.5086152806,
               7.84702e-5,
               20_449_136_107,
               643_178_477
             ]
           ]

    # Test Bitcoin Cash is in influx
    assert Store.fetch_price_points!(@bch_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-11-08 10:38:39], "Etc/UTC"),
               596.873154491,
               0.0920867701,
               10_413_526_552,
               924_146_674
             ]
           ]

    # Test EOS is in influx
    assert Store.fetch_price_points!(@eos_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-11-08 10:38:32], "Etc/UTC"),
               5.554970117,
               8.570318e-4,
               5_034_164_547,
               698_336_214
             ]
           ]
  end
end
