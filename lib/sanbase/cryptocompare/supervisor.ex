defmodule Sanbase.Cryptocompare.Supervisor do
  use Supervisor

  import Sanbase.ApplicationUtils

  alias Sanbase.Utils.Config

  alias Sanbase.Cryptocompare.{WebsocketScraper, HistoricalScheduler}

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
      [
        # Websocket realtime price exporter
        start_if(
          fn -> WebsocketScraper end,
          fn -> WebsocketScraper.enabled?() end
        ),
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
          fn -> WebsocketScraper.enabled?() or HistoricalScheduler.enabled?() end
        ),
        # Kafka exporter for the websocket price exporter
        start_if(
          fn ->
            Sanbase.KafkaExporter.child_spec(
              id: :asset_price_pairs_exporter,
              name: :asset_price_pairs_exporter,
              topic: Config.module_get!(Sanbase.KafkaExporter, :asset_price_pairs_topic),
              buffering_max_messages: 1000,
              can_send_after_interval: 250,
              kafka_flush_timeout: 1000
            )
          end,
          fn -> WebsocketScraper.enabled?() end
        ),
        start_if(
          fn -> HistoricalScheduler end,
          fn -> HistoricalScheduler.enabled?() end
        )
      ]
      |> normalize_children()

    Supervisor.init(children, strategy: :one_for_one)
  end
end
