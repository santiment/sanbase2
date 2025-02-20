defmodule Sanbase.Cryptocompare.HistoricalWorker.OHLCVPriceTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2]
  import Sanbase.Cryptocompare.HistoricalDataStub, only: [ohlcv_price_data: 3]

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

    Sanbase.Cryptocompare.Price.HistoricalScheduler.add_jobs(base_asset, quote_asset, from, to)

    Sanbase.Mock.prepare_mock(HTTPoison, :get, fn url, _header, _ops ->
      # return different timestamps for every date
      [_, date_str] = Regex.split(~r/\d{4}-\d{2}-\d{2}/, url, include_captures: true, trim: true)

      ohlcv_price_data(base_asset, quote_asset, date_str)
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Cryptocompare.Price.HistoricalScheduler.resume()

      # Assert that all the jobs are enqueued
      for date <- generate_dates_inclusive(from, to) do
        assert_enqueued(
          worker: Sanbase.Cryptocompare.Price.HistoricalWorker,
          args: %{
            base_asset: base_asset,
            quote_asset: quote_asset,
            date: date |> to_string()
          }
        )
      end

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 10, failure: 0} =
               Oban.drain_queue(Sanbase.Cryptocompare.Price.HistoricalScheduler.conf_name(),
                 queue: Sanbase.Cryptocompare.Price.HistoricalWorker.queue()
               )

      state = Sanbase.InMemoryKafka.Producer.get_state()

      price_pairs_only_topic = state["asset_price_pairs_only"]
      assert length(price_pairs_only_topic) == 200

      price_pairs_only_topic =
        Enum.map(price_pairs_only_topic, fn {k, v} -> {k, Jason.decode!(v)} end)

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609718400",
              Jason.decode!(
                "{\"base_asset\":\"#{base_asset}\",\"price\":6250.308944432027,\"quote_asset\":\"USD\",\"source\":\"cryptocompare\",\"timestamp\":1609718400}"
              )} in price_pairs_only_topic

      assert {"cryptocompare_#{base_asset}_#{quote_asset}_1609977840",
              Jason.decode!(
                "{\"base_asset\":\"#{base_asset}\",\"price\":6217.993237443811,\"quote_asset\":\"USD\",\"source\":\"cryptocompare\",\"timestamp\":1609977840}"
              )} in price_pairs_only_topic
    end)

    # Seems to fix some error
    Sanbase.Cryptocompare.Price.HistoricalScheduler.pause()
  end
end
