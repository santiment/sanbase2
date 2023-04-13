defmodule Sanbase.Cryptocompare.FundingRateHistoricalWorkerTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Cryptocompare.HistoricalDataStub, only: [funding_rate_data: 4]

  alias Sanbase.Cryptocompare.FundingRate

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()

    %{
      market: "binance",
      instrument: "ETH-USDT-VANILLA-PERPETUAL",
      timestamp: ~U[2023-02-01 00:00:00Z] |> DateTime.to_unix(),
      limit: 24,
      queue: FundingRate.HistoricalWorker.queue()
    }
  end

  test "schedule work and scrape data", context do
    %{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      limit: limit,
      queue: queue
    } = context

    FundingRate.HistoricalScheduler.add_job(
      market,
      instrument,
      timestamp,
      _schdule_previous_job = true,
      limit
    )

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn url, _header, _ops ->
      mocked_url_response(url)
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      FundingRate.HistoricalScheduler.resume()

      assert Sanbase.Cryptocompare.ExporterProgress.get_timestamps(
               "#{market}_#{instrument}",
               to_string(queue)
             ) == nil

      # Test that the manually added job above via `add_job/4` is scheduled j
      assert_enqueued(
        worker: FundingRate.HistoricalWorker,
        args: %{
          market: market,
          instrument: instrument,
          timestamp: timestamp,
          schedule_next_job: true,
          limit: limit
        }
      )

      # There is no such job yet. It will be scheduled when a job executes
      refute_enqueued(
        worker: FundingRate.HistoricalWorker,
        args: %{
          market: market,
          instrument: instrument,
          schedule_next_job: true,
          timestamp: timestamp - (limit - 1) * 3600,
          limit: limit
        }
      )

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 1, failure: 0} =
               Oban.drain_queue(
                 FundingRate.HistoricalScheduler.conf_name(),
                 queue: FundingRate.HistoricalWorker.queue()
               )

      # Performing a job will enqueue a new one to scrape the data before that
      assert_enqueued(
        worker: FundingRate.HistoricalWorker,
        args: %{
          limit: 2000,
          market: market,
          instrument: instrument,
          schedule_next_job: true,
          timestamp: timestamp - (limit - 1) * 3600
        }
      )

      state = Sanbase.InMemoryKafka.Producer.get_state()
      topic = state["funding_rate_cryptocompare"]

      assert length(topic) == limit

      for i <- (limit - 1)..0 do
        assert {"#{market}_#{instrument}_#{timestamp - i * 3600}",
                "{\"close\":0.01,\"contract_currency\":\"ETH\",\"instrument\":\"#{instrument}\",\"mapped_instrument\":\"ETH-USDT-VANILLA-PERPETUAL\",\"market\":\"binance\",\"quote_currency\":\"USDT\",\"settlement_currency\":\"USDT\",\"timestamp\":#{timestamp - i * 3600}}"} in topic
      end
    end)

    {min_timestamp, max_timestamp} =
      Sanbase.Cryptocompare.ExporterProgress.get_timestamps(
        "#{market}_#{instrument}",
        to_string(queue)
      )

    assert min_timestamp == timestamp - (limit - 1) * 3600
    assert max_timestamp == timestamp

    # Seems to fix some error
    FundingRate.HistoricalScheduler.pause()
  end

  test "exporter progress is used to limit the export", context do
    %{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      limit: limit
    } = context

    # Schedule 10 jobs each, scraping `limit` hours. Each job
    # is 1 hour after the previous. The expected number of
    # non-overlapped hours is limit + 10
    for i <- 10..0 do
      FundingRate.HistoricalScheduler.add_job(
        market,
        instrument,
        timestamp - i * 3600,
        _schdule_previous_job = false,
        limit
      )
    end

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn url, _header, _ops ->
      mocked_url_response(url)
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      FundingRate.HistoricalScheduler.resume()
      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 11, failure: 0} =
               Oban.drain_queue(
                 FundingRate.HistoricalScheduler.conf_name(),
                 queue: FundingRate.HistoricalWorker.queue()
               )

      state = Sanbase.InMemoryKafka.Producer.get_state()
      topic = state["funding_rate_cryptocompare"]

      # The number of non-overlapped hours is limit + 10
      assert length(topic) == limit + 10
    end)

    FundingRate.HistoricalScheduler.pause()
  end

  defp mocked_url_response(url) do
    %{"to_ts" => timestamp, "limit" => limit, "market" => market, "instrument" => instrument} =
      URI.parse(url).query
      |> URI.decode_query()

    funding_rate_data(
      market,
      instrument,
      String.to_integer(timestamp),
      String.to_integer(limit)
    )
  end
end
