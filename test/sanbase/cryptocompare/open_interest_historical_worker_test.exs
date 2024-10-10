defmodule Sanbase.Cryptocompare.OpenInterestHistoricalWorkerTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Cryptocompare.HistoricalDataStub, only: [open_interest_data: 4]

  alias Sanbase.Cryptocompare.OpenInterest

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()

    %{
      market: "binance",
      instrument: "ETH-USDT-VANILLA-PERPETUAL",
      timestamp: ~U[2023-02-01 00:00:00Z] |> DateTime.to_unix(),
      limit: 24,
      queue: OpenInterest.HistoricalWorker.queue()
    }
  end

  test "schedule jobs with different versions", context do
    %{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      limit: limit,
      queue: queue
    } = context

    assert {:ok, _} =
             OpenInterest.HistoricalScheduler.add_job(
               market,
               instrument,
               timestamp,
               true,
               limit,
               "v1"
             )

    assert {:ok, _} =
             OpenInterest.HistoricalScheduler.add_job(
               market,
               instrument,
               timestamp,
               true,
               limit,
               "v2"
             )

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn url, _header, _ops ->
      mocked_url_response(url)
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      OpenInterest.HistoricalScheduler.resume()

      assert Sanbase.Cryptocompare.ExporterProgress.get_timestamps(
               "#{market}_#{instrument}",
               to_string(queue)
             ) == nil

      assert Sanbase.Cryptocompare.ExporterProgress.get_timestamps(
               "#{market}_#{instrument}_v2",
               to_string(queue)
             ) == nil

      # Test that the manually added job above via `add_job/4` is scheduled j
      assert_enqueued(
        worker: OpenInterest.HistoricalWorker,
        args: %{
          market: market,
          instrument: instrument,
          timestamp: timestamp,
          schedule_next_job: true,
          limit: limit,
          version: "v1"
        }
      )

      # Test that the manually added job above via `add_job/4` is scheduled j
      assert_enqueued(
        worker: OpenInterest.HistoricalWorker,
        args: %{
          market: market,
          instrument: instrument,
          timestamp: timestamp,
          schedule_next_job: true,
          limit: limit,
          version: "v2"
        }
      )

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 2, failure: 0} =
               Oban.drain_queue(
                 OpenInterest.HistoricalScheduler.conf_name(),
                 queue: OpenInterest.HistoricalWorker.queue()
               )

      assert_enqueued(
        worker: OpenInterest.HistoricalWorker,
        args: %{
          limit: limit,
          market: market,
          instrument: instrument,
          schedule_next_job: true,
          timestamp: timestamp - (limit - 1) * 3600,
          version: "v1"
        }
      )

      assert_enqueued(
        worker: OpenInterest.HistoricalWorker,
        args: %{
          limit: limit,
          market: market,
          instrument: instrument,
          schedule_next_job: true,
          timestamp: timestamp - (limit - 1) * 3600,
          version: "v2"
        }
      )

      kafka_message = fn market, instrument, timestamp, i ->
        {"#{market}_#{instrument}_#{timestamp - i * 3600}",
         Jason.decode!(
           "{\"close_mark_price\":1332.98969276,\"close_quote\":187708030,\"close_settlement\":140817.31540725136,\"contract_currency\":\"USD\",\"instrument\":\"ETHUSD_PERP\",\"mapped_instrument\":\"#{instrument}\",\"market\":\"#{market}\",\"quote_currency\":\"USD\",\"settlement_currency\":\"ETH\",\"timestamp\":#{timestamp - i * 3600}}"
         )}
      end

      state = Sanbase.InMemoryKafka.Producer.get_state()

      # The v1 topic
      topic = state["open_interest_cryptocompare"]

      assert length(topic) == limit
      topic = Enum.map(topic, fn {k, v} -> {k, Jason.decode!(v)} end)

      for i <- (limit - 1)..0//-1 do
        assert kafka_message.(market, instrument, timestamp, i) in topic
      end

      # The v2 topic

      topic = state["open_interest_cryptocompare_v2"]

      assert length(topic) == limit
      topic = Enum.map(topic, fn {k, v} -> {k, Jason.decode!(v)} end)

      for i <- (limit - 1)..0//-1 do
        assert {"#{market}_#{instrument}_#{timestamp - i * 3600}",
                Jason.decode!(
                  "{\"close_mark_price\":1332.98969276,\"close_quote\":187708030,\"close_settlement\":140817.31540725136,\"contract_currency\":\"USD\",\"instrument\":\"ETHUSD_PERP\",\"mapped_instrument\":\"#{instrument}\",\"market\":\"#{market}\",\"quote_currency\":\"USD\",\"settlement_currency\":\"ETH\",\"timestamp\":#{timestamp - i * 3600}}"
                )} in topic
      end
    end)
  end

  test "schedule work and scrape data", context do
    %{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      limit: limit,
      queue: queue
    } = context

    OpenInterest.HistoricalScheduler.add_job(
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
      OpenInterest.HistoricalScheduler.resume()

      assert Sanbase.Cryptocompare.ExporterProgress.get_timestamps(
               "#{market}_#{instrument}",
               to_string(queue)
             ) == nil

      # Test that the manually added job above via `add_job/4` is scheduled j
      assert_enqueued(
        worker: OpenInterest.HistoricalWorker,
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
        worker: OpenInterest.HistoricalWorker,
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
                 OpenInterest.HistoricalScheduler.conf_name(),
                 queue: OpenInterest.HistoricalWorker.queue()
               )

      # Performing a job will enqueue a new one to scrape the data before that
      assert_enqueued(
        worker: OpenInterest.HistoricalWorker,
        args: %{
          limit: limit,
          market: market,
          instrument: instrument,
          schedule_next_job: true,
          timestamp: timestamp - (limit - 1) * 3600,
          version: "v1"
        }
      )

      state = Sanbase.InMemoryKafka.Producer.get_state()
      topic = state["open_interest_cryptocompare"]

      assert length(topic) == limit
      topic = Enum.map(topic, fn {k, v} -> {k, Jason.decode!(v)} end)

      for i <- (limit - 1)..0//-1 do
        assert {"#{market}_#{instrument}_#{timestamp - i * 3600}",
                Jason.decode!(
                  "{\"close_mark_price\":1332.98969276,\"close_quote\":187708030,\"close_settlement\":140817.31540725136,\"contract_currency\":\"USD\",\"instrument\":\"ETHUSD_PERP\",\"mapped_instrument\":\"#{instrument}\",\"market\":\"#{market}\",\"quote_currency\":\"USD\",\"settlement_currency\":\"ETH\",\"timestamp\":#{timestamp - i * 3600}}"
                )} in topic
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
    OpenInterest.HistoricalScheduler.pause()
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
    for i <- 10..0//-1 do
      OpenInterest.HistoricalScheduler.add_job(
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
      OpenInterest.HistoricalScheduler.resume()
      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 11, failure: 0} =
               Oban.drain_queue(
                 OpenInterest.HistoricalScheduler.conf_name(),
                 queue: OpenInterest.HistoricalWorker.queue()
               )

      state = Sanbase.InMemoryKafka.Producer.get_state()
      topic = state["open_interest_cryptocompare"]

      # The number of non-overlapped hours is limit + 10
      assert length(topic) == limit + 10
    end)

    OpenInterest.HistoricalScheduler.pause()
  end

  defp mocked_url_response(url) do
    %{"to_ts" => timestamp, "limit" => limit, "market" => market, "instrument" => instrument} =
      URI.parse(url).query
      |> URI.decode_query()

    open_interest_data(
      market,
      instrument,
      String.to_integer(timestamp),
      String.to_integer(limit)
    )
  end
end
