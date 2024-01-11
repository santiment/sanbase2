defmodule Sanbase.Kafka.Consumer do
  require Sanbase.Utils.Config, as: Config
  require Logger

  def init do
    case enabled?() do
      true ->
        config =
          Application.get_env(:kaffe, :consumer)
          |> Keyword.merge(
            endpoints: endpoints(),
            topics: topics(),
            # generate unique consumer group on boot
            consumer_group:
              consumer_group_basename() <>
                "_" <> (:crypto.strong_rand_bytes(4) |> Base.encode64(padding: false))
          )

        Application.put_env(:kaffe, :consumer, config)

        Logger.info(
          "Kafka consumer configuration: #{inspect(Kaffe.Config.Consumer.configuration())}"
        )

        :ok

      false ->
        Logger.info("Sanbase.Kafka.Consumer is not enabled and won't be started")
        {:error, :not_started}
    end
  end

  def enabled? do
    env = Config.module_get(Sanbase, :env)
    kafka_conusmer_enabled? = Config.module_get_boolean(__MODULE__, :enabled?)

    env in [:dev, :prod] and kafka_conusmer_enabled?
  end

  defp topics do
    # string like: "topic1, topic2 ..."
    Config.module_get(__MODULE__, :metrics_stream_topic)
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp endpoints() do
    # Locally, we need to provide all 3 endpoints as exposed through the VPN In
    # the stage/prod clusters a single endpoint is sufficient. Because of this
    # the endpoints are handled like this - one kafka_url and one or more comma
    # separated ports. The results then are zipped together to form a list of
    # tuple endpoints like {host, port}
    kafka_url = Config.module_get(Sanbase.Kafka, :kafka_url)

    kafka_ports =
      Config.module_get(Sanbase.Kafka, :kafka_port)
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(fn port -> port |> String.trim() |> Sanbase.Math.to_integer() end)

    kafka_urls = Stream.cycle([kafka_url])
    Enum.zip(kafka_urls, kafka_ports)
  end

  defp consumer_group_basename(), do: Config.module_get(__MODULE__, :consumer_group_basename)
end
