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
      %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "v1_ticker_5.json"))}
    end)

    Store.drop_measurement(@btc_measurement)
    Store.drop_measurement(@eth_measurement)
    Store.drop_measurement(@xrp_measurement)
    Store.drop_measurement(@bch_measurement)
    Store.drop_measurement(@eos_measurement)

    TickerFetcher.work()

    from = DateTime.from_naive!(~N[2018-05-20 22:15:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2018-05-22 22:15:00], "Etc/UTC")

    # Test bitcoin is in influx
    assert Store.fetch_price_points!(@btc_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-05-21 13:34:30], "Etc/UTC"),
               8492.42,
               1,
               144_762_215_941,
               5_442_600_000
             ]
           ]

    # Test Ethereum is in influx
    assert Store.fetch_price_points!(@eth_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-05-21 13:34:18], "Etc/UTC"),
               708.686,
               0.0833915,
               70_566_984_832,
               2_160_260_000
             ]
           ]

    # Test Ripple is in influx
    assert Store.fetch_price_points!(@xrp_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-05-21 13:34:03], "Etc/UTC"),
               0.689748,
               8.116e-5,
               27_031_202_213,
               281_028_000
             ]
           ]

    # Test Bitcoin Cash is in influx
    assert Store.fetch_price_points!(@bch_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-05-21 13:34:13], "Etc/UTC"),
               1251.63,
               0.14728,
               21_452_562_711,
               726_915_000
             ]
           ]

    # Test EOS is in influx
    assert Store.fetch_price_points!(@eos_measurement, from, to) == [
             [
               DateTime.from_naive!(~N[2018-05-21 13:34:12], "Etc/UTC"),
               13.5937,
               0.00159958,
               11_833_771_308,
               1_197_690_000
             ]
           ]
  end
end
