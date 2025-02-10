defmodule Sanbase.Cryptocompare.Supervisor do
  @moduledoc false
  use Supervisor

  import Sanbase.ApplicationUtils

  alias Sanbase.Cryptocompare.FundingRate
  alias Sanbase.Cryptocompare.OpenInterest
  alias Sanbase.Cryptocompare.Price
  alias Sanbase.Utils.Config

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      type: :supervisor,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def init(_opts) do
    children =
      normalize_children([
        start_if(
          fn ->
            Sanbase.KafkaExporter.child_spec(
              id: :asset_price_pairs_only_exporter,
              name: :asset_price_pairs_only_exporter,
              topic: Config.module_get!(Sanbase.KafkaExporter, :asset_price_pairs_only_topic),
              buffering_max_messages: 1000,
              can_send_after_interval: 250,
              kafka_flush_timeout: 1000
            )
          end,
          fn -> Price.WebsocketScraper.enabled?() or Price.HistoricalScheduler.enabled?() end
        ),
        start_if(
          fn ->
            Sanbase.KafkaExporter.child_spec(
              id: :open_interest_exporter,
              name: :open_interest_exporter,
              topic: Config.module_get!(Sanbase.KafkaExporter, :open_interest_topic),
              buffering_max_messages: 5000,
              can_send_after_interval: 250,
              kafka_flush_timeout: 1000
            )
          end,
          fn -> OpenInterest.HistoricalScheduler.enabled?() end
        ),
        start_if(
          fn ->
            Sanbase.KafkaExporter.child_spec(
              id: :funding_rate_exporter,
              name: :funding_rate_exporter,
              topic: Config.module_get!(Sanbase.KafkaExporter, :funding_rate_topic),
              buffering_max_messages: 5000,
              can_send_after_interval: 250,
              kafka_flush_timeout: 1000
            )
          end,
          fn -> FundingRate.HistoricalScheduler.enabled?() end
        ),
        start_if(fn -> Price.WebsocketScraper end, fn -> Price.WebsocketScraper.enabled?() end),
        start_if(fn -> Price.HistoricalScheduler end, fn -> Price.HistoricalScheduler.enabled?() end),
        start_if(fn -> OpenInterest.HistoricalScheduler end, fn -> OpenInterest.HistoricalScheduler.enabled?() end),
        start_if(fn -> FundingRate.HistoricalScheduler end, fn -> FundingRate.HistoricalScheduler.enabled?() end)
      ])

    # Both the historical and realtime websocket scrapers export to that topic
    # Kafka exporter for the open interest scraper
    # Kafka exporter for the funding rate scraper
    # Websocket realtime price exporter
    # Resume and pause on termination the price historical queue
    # Resume and pause on termination the open interest historical queue
    # Resume and pause on termination the funding rate historical queue
    Supervisor.init(children, strategy: :one_for_one)
  end
end
