defmodule Sanbase.Application do
  use Application

  import Sanbase.ApplicationUtils

  require Logger
  require Sanbase.Utils.Config, as: Config

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    if Code.ensure_loaded?(Envy) do
      Envy.auto_load()
    end

    container_type = System.get_env("CONTAINER_TYPE") || "all"

    init(container_type)

    {children, opts} =
      case container_type do
        "web" ->
          Logger.info("Starting Web Sanbase.")
          Sanbase.Application.Web.children()

        "scrapers" ->
          Logger.info("Starting Scrapers Sanbase.")
          Sanbase.Application.Scrapers.children()

        "signals" ->
          Logger.info("Starting Signals Sanbase.")
          Sanbase.Application.Signals.children()

        "all" ->
          Logger.info("Start all Sanbase container types.")
          {web_children, _} = Sanbase.Application.Web.children()
          {scrapers_children, _} = Sanbase.Application.Scrapers.children()
          {signals_children, _} = Sanbase.Application.Signals.children()

          children = web_children ++ scrapers_children ++ signals_children
          children = children |> Enum.uniq()

          opts = [
            strategy: :one_for_one,
            name: Sanbase.Supervisor,
            max_restarts: 5,
            max_seconds: 1
          ]

          {children, opts}

        unknown_type ->
          Logger.warn(
            "Unkwnown container type provided - #{inspect(unknown_type)}. Will start a default web container."
          )

          Logger.info("Starting Web Sanbase.")
          Sanbase.Application.Web.children()
      end

    prepended_children =
      prepended_children(container_type) ++ prepend_api_call_exporter_children(container_type)

    children =
      (prepended_children ++ common_children() ++ children)
      |> Sanbase.ApplicationUtils.normalize_children()
      |> Enum.uniq()

    # Add error tracking through sentry
    {:ok, _} = Logger.add_backend(Sentry.LoggerBackend)
    Supervisor.start_link(children, opts)
  end

  @spec init(String.t()) :: :ok | [any()]
  def init(container_type) do
    # Common inits

    # Increase the backtrace depth here and not in the phoenix config
    # so it applies to all non-phoenix work, too
    :erlang.system_flag(:backtrace_depth, 20)

    # Prometheus related
    Sanbase.Prometheus.EctoInstrumenter.setup()

    Sanbase.Prometheus.PipelineInstrumenter.setup()

    Sanbase.Prometheus.Exporter.setup()

    # Container specific init
    case container_type do
      "all" ->
        Sanbase.Application.Web.init()
        Sanbase.Application.Scrapers.init()
        Sanbase.Application.Signals.init()

      "web" ->
        Sanbase.Application.Web.init()

      "signals" ->
        Sanbase.Application.Signals.init()

      "scrapers" ->
        Sanbase.Application.Scrapers.init()

      _ ->
        Sanbase.Application.Web.init()
    end
  end

  @doc ~s"""
  Some services must be started before all others
  """
  def prepended_children(container_type) when container_type in ["all", "scrapers"] do
    [
      # Start the Kafka Exporter
      {SanExporterEx,
       [
         kafka_producer_module: kafka_producer_supervisor_module(),
         kafka_endpoint: kafka_endpoint()
       ]},
      Supervisor.child_spec(
        {Sanbase.KafkaExporter,
         [
           name: :prices_exporter,
           topic: kafka_prices_data_topic(),
           buffering_max_messages: 10_000,
           can_send_after_interval: 200
         ]},
        id: :prices_exporter
      )
    ]
  end

  def prepended_children(_), do: []

  def prepend_api_call_exporter_children(container_type) when container_type in ["web", "all"] do
    [
      # Start the Kafka Exporter
      {SanExporterEx,
       [
         kafka_producer_module: kafka_producer_supervisor_module(),
         kafka_endpoint: kafka_endpoint()
       ]},

      # Start the API Call Data Exporter. Must be started before the Endpoint
      # so it will be terminated after the Endpoint so no API Calls can come in
      # and not be persisted. When terminating it will flush its internal buffer
      Supervisor.child_spec(
        {Sanbase.KafkaExporter, [name: :api_call_exporter, topic: kafka_api_call_data_topic()]},
        id: :api_call_exporter
      )
    ]
  end

  def prepend_api_call_exporter_children(_), do: []

  @doc ~s"""
  Children common for all types of container types
  """
  @spec common_children() :: [:supervisor.child_spec() | {module(), term()} | module()]
  def common_children() do
    [
      # Start the endpoint when the application starts
      SanbaseWeb.Endpoint,

      # Start the Postgres Ecto repository
      Sanbase.Repo,

      # Start the PubSub
      {Phoenix.PubSub, name: Sanbase.PubSub},

      # Telemetry metrics
      SanbaseWeb.Telemetry,

      # Start the Clickhouse Repo
      start_if(
        fn -> Sanbase.ClickhouseRepo end,
        fn ->
          Application.get_env(:sanbase, :env) in [:dev, :prod] and
            Sanbase.ClickhouseRepo.enabled?()
        end
      ),

      # Star the API call service
      Sanbase.ApiCallLimit.ETS,

      # Time series Prices DB connection
      Sanbase.Prices.Store.child_spec(),

      # Start the Task Supervisor
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

      # Mutex for forcing sequential execution when updating api call limits
      Supervisor.child_spec(
        {Mutex, name: Sanbase.ApiCallLimitMutex},
        id: Sanbase.ApiCallLimitMutex
      ),

      # Start telegram rate limiter. Used both in web and signals
      Sanbase.ExternalServices.RateLimiting.Server.child_spec(
        :telegram_bot_rate_limiting_server,
        scale: 1000,
        limit: 30,
        time_between_requests: 10
      ),

      # General purpose cache available in all types
      Supervisor.child_spec(
        {ConCache,
         [
           name: Sanbase.Cache.name(),
           ttl_check_interval: :timer.seconds(30),
           global_ttl: :timer.minutes(5),
           acquire_lock_timeout: 30_000
         ]},
        id: :sanbase_generic_cache
      ),

      # Service for fast checking if a slug is valid
      # `:available_slugs_module` option changes the module
      # used in test env to another one, this one is unused
      start_in(Sanbase.AvailableSlugs, [:dev, :prod]),

      # Process that starts test-only deps
      start_in(Sanbase.TestSetupService, [:test])
    ]
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp kafka_producer_supervisor_module() do
    Config.module_get(Sanbase.KafkaExporter, :supervisor)
  end

  defp kafka_api_call_data_topic() do
    Config.module_get(Sanbase.KafkaExporter, :api_call_data_topic)
  end

  defp kafka_prices_data_topic() do
    Config.module_get(Sanbase.KafkaExporter, :prices_topic)
  end

  defp kafka_endpoint() do
    url = Config.module_get(Sanbase.KafkaExporter, :kafka_url) |> to_charlist()

    port = Config.module_get(Sanbase.KafkaExporter, :kafka_port) |> Sanbase.Math.to_integer()

    [{url, port}]
  end
end
