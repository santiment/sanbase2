defmodule Sanbase.Hyperliquid.Supervisor do
  use Supervisor

  import Sanbase.ApplicationUtils

  alias Sanbase.Hyperliquid.Bbo.WebsocketScraper
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
      [
        start_if(
          fn ->
            Sanbase.KafkaExporter.child_spec(
              id: :hyperliquid_bbo_exporter,
              name: :hyperliquid_bbo_exporter,
              topic: Config.module_get!(Sanbase.KafkaExporter, :hyperliquid_bbo_topic),
              buffering_max_messages: 10_000,
              can_send_after_interval: 100,
              kafka_flush_timeout: 250
            )
          end,
          fn -> WebsocketScraper.enabled?() end
        ),
        start_if(
          fn -> WebsocketScraper end,
          fn -> WebsocketScraper.enabled?() end
        )
      ]
      |> normalize_children()

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
