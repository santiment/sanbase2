defmodule Sanbase.Kafka.Exporter.Prices do
  require Sanbase.Utils.Config, as: Config

  @topic Config.get(:topic, "sanbase_prices")
  @producer Config.get(:producer, SanExporterEx.Producer)

  def topic, do: @topic

  def persist_async(messages) do
    @producer.send_data_async(@topic, messages)
  end
end
