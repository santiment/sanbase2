defmodule Sanbase.Kafka do
  require Sanbase.Utils.Config, as: Config
  require Logger

  def init do
    config = Application.get_env(:kaffe, :consumer)

    new_values = [
      endpoints: endpoints(),
      topics: topics(),
      # generate unique consumer group on boot
      consumer_group: consumer_group_basename() <> Ecto.UUID.generate()
    ]

    new_config = Keyword.merge(config, new_values)

    Application.put_env(:kaffe, :consumer, new_config)

    Logger.info("Kafka consumer configuration: #{inspect(Kaffe.Config.Consumer.configuration())}")
  end

  defp topics do
    # string like: "topic1, topic2 ..."
    Config.get(:topics)
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp endpoints do
    [
      {Config.get(:url), Config.get(:port) |> String.to_integer()}
    ]
  end

  defp consumer_group_basename do
    Config.get(:consumer_group_basename)
  end
end
