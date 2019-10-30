defmodule Sanbase.Kafka do
  require Sanbase.Utils.Config, as: Config
  require Logger

  def init do
    config = Application.get_env(:kaffe, :consumer)

    new_values = [
      endpoints: endpoints(),
      topics: topics(),
      consumer_group: Keyword.get(config, :consumer_group) <> Ecto.UUID.generate()
    ]

    new_config = Keyword.merge(config, new_values)

    Application.put_env(:kaffe, :consumer, new_config)

    Logger.info("Kafka consumer configuration: #{inspect(Kaffe.Config.Consumer.configuration())}")
  end

  def topics do
    # string like: "topic1, topic2 ..."
    Config.get(:topics)
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  def endpoints do
    [
      {Config.get(:kafka_url), Config.get(:kafka_port) |> String.to_integer()}
    ]
  end
end
