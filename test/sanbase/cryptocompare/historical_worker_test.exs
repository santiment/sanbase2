defmodule Sanbase.Cryptocompare.HistoricalWorkerTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2]
  import Sanbase.Cryptocompare.HistoricalDataStub, only: [http_call_data: 3]

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()
    project = insert(:random_erc20_project)

    mapping =
      insert(:source_slug_mapping,
        source: "cryptocompare",
        slug: project.ticker,
        project_id: project.id
      )

    %{
      project: project,
      project_cpc_name: mapping.slug,
      base_asset: mapping.slug,
      quote_asset: "USD"
    }
  end

  test "schedule work and scrape data", context do
    %{base_asset: base_asset, quote_asset: quote_asset} = context
    from = ~D[2021-01-01]
    to = ~D[2021-01-10]

    Sanbase.Cryptocompare.HistoricalScheduler.add_jobs(base_asset, quote_asset, from, to)

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn url, _header, _ops ->
      # return different timestamps for every date
      [_, date_str] = Regex.split(~r/\d{4}-\d{2}-\d{2}/, url, include_captures: true, trim: true)

      http_call_data(base_asset, quote_asset, date_str)
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Cryptocompare.HistoricalScheduler.resume()

      # Assert that all the jobs are enqueued
      for date <- generate_dates_inclusive(from, to) do
        assert_enqueued(
          worker: Sanbase.Cryptocompare.HistoricalWorker,
          args: %{
            base_asset: base_asset,
            quote_asset: quote_asset,
            date: date |> to_string()
          }
        )
      end

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 10, failure: 0} =
               Oban.drain_queue(Sanbase.Cryptocompare.HistoricalScheduler.conf_name(),
                 queue: Sanbase.Cryptocompare.HistoricalWorker.queue()
               )

      state = Sanbase.InMemoryKafka.Producer.get_state()
      ohlcv_topic = state["asset_ohlcv_price_pairs"]

      # 10 days with 20 records in each
      assert length(ohlcv_topic) == 200

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609978320",
              "{\"base_asset\":\"#{base_asset}\",\"close\":6205.778967271624,\"high\":6206.719787115138,\"interval_seconds\":60,\"low\":6189.903645170898,\"open\":6189.526529700908,\"quote_asset\":\"#{quote_asset}\",\"source\":\"cryptocompare\",\"timestamp\":1609978320,\"volume_from\":63.31105002899999,\"volume_to\":392518.1490704502}"} in ohlcv_topic

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609546680",
              "{\"base_asset\":\"#{base_asset}\",\"close\":6208.7051725246765,\"high\":6209.396411564128,\"interval_seconds\":60,\"low\":6207.223419819188,\"open\":6209.099140044042,\"quote_asset\":\"#{quote_asset}\",\"source\":\"cryptocompare\",\"timestamp\":1609546680,\"volume_from\":11.45305277,\"volume_to\":71041.48491074912}"} in ohlcv_topic

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609804800",
              "{\"base_asset\":\"#{base_asset}\",\"close\":6250.308944432027,\"high\":6267.326355454034,\"interval_seconds\":60,\"low\":6240.674651886244,\"open\":6241.908080470284,\"quote_asset\":\"#{quote_asset}\",\"source\":\"cryptocompare\",\"timestamp\":1609804800,\"volume_from\":248.36219959,\"volume_to\":1553761.3212507297}"} in ohlcv_topic

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609891620",
              "{\"base_asset\":\"#{base_asset}\",\"close\":6208.461799608979,\"high\":6217.102504984712,\"interval_seconds\":60,\"low\":6206.278670187404,\"open\":6217.0036048556485,\"quote_asset\":\"#{quote_asset}\",\"source\":\"cryptocompare\",\"timestamp\":1609891620,\"volume_from\":45.82058862,\"volume_to\":284268.99153977534}"} in ohlcv_topic

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1610064120",
              "{\"base_asset\":\"#{base_asset}\",\"close\":6197.939996238564,\"high\":6242.094267553671,\"interval_seconds\":60,\"low\":6197.939996238564,\"open\":6242.400315239814,\"quote_asset\":\"#{quote_asset}\",\"source\":\"cryptocompare\",\"timestamp\":1610064120,\"volume_from\":402.73847456,\"volume_to\":2496888.8341799136}"} in ohlcv_topic

      price_pairs_only_topic = state["asset_price_pairs_only"]
      assert length(price_pairs_only_topic) == 200

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609718400",
              "{\"base_asset\":\"#{base_asset}\",\"price\":6250.308944432027,\"quote_asset\":\"USD\",\"source\":\"cryptocompare\",\"timestamp\":1609718400}"} in price_pairs_only_topic

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609977840",
              "{\"base_asset\":\"#{base_asset}\",\"price\":6217.993237443811,\"quote_asset\":\"USD\",\"source\":\"cryptocompare\",\"timestamp\":1609977840}"} in price_pairs_only_topic
    end)

    # Seems to fix some error
    Sanbase.Cryptocompare.HistoricalScheduler.pause()
  end
end
