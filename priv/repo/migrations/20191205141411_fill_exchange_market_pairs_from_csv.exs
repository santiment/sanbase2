defmodule Sanbase.Repo.Migrations.FillExchangeMarketPairsFromCsv do
  use Ecto.Migration

  alias Sanbase.Exchanges.MarketPairMapping
  @source "coinmarketcap"

  def up do
    setup()

    data =
      Path.expand("exchange_market_pairs_final.csv", __DIR__)
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(fn line ->
        [exchange, market_pair, from_slug, to_slug, from_ticker, to_ticker] =
          String.split(line, ",", trim: true)

        %{
          exchange: String.capitalize(exchange),
          market_pair: market_pair,
          from_slug: from_slug,
          to_slug: to_slug,
          from_ticker: from_ticker,
          to_ticker: to_ticker,
          source: @source,
          inserted_at: Timex.now(),
          updated_at: Timex.now()
        }
      end)

    Sanbase.Repo.insert_all(MarketPairMapping, data)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
