defmodule Sanbase.Application do
  use Application

  import Sanbase.ApplicationUtils

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.EventBus.KafkaExporterSubscriber

  def start(_type, _args) do
    Code.ensure_loaded?(Envy) && Envy.auto_load()

    # Container type is one of: web, scrapers, signals, all
    container_type = container_type()

    print_starting_log(container_type)

    # Do some initialization. This includes increasing the backtrace depth,
    # setting up some monitoring instruments, etc.
    init(container_type)

    # Get the proper children that have to be started in the current container type
    {children, opts} = children_opts(container_type)

    # Some of the children must be expliclitly started before others. Because the
    # container type `all` is a combination of all other container types, we need to
    # additionally prepend these children, otherwise they can end up in the middle
    # of the list
    prepended_children = prepended_children(container_type)

    # This list contains all children that are common to all container types. These
    # include some Ecto adapters, Telemetry, Phoenix Endpoint, etc.
    common_children = common_children()

    # Combine all the children to be started. Run a normalization. This normalization
    # takes care of the results of some custom `start_in` and `start_if` custom cases.
    # They might return `nil` to signal that they don't have to be started and these
    # values need to be cleaned.
    children =
      (prepended_children ++ common_children ++ children)
      |> Sanbase.ApplicationUtils.normalize_children()
      |> Enum.uniq()

    # Add error tracking through sentry
    {:ok, _} = Logger.add_backend(Sentry.LoggerBackend)
    Supervisor.start_link(children, opts)
  end

  def init(container_type) do
    # Increase the backtrace depth here and not in the phoenix config
    # so it applies to all non-phoenix work, too
    :erlang.system_flag(:backtrace_depth, 20)

    # Prometheus related
    Sanbase.Prometheus.EctoInstrumenter.setup()
    Sanbase.Prometheus.PipelineInstrumenter.setup()
    Sanbase.Prometheus.Exporter.setup()

    Sanbase.EventBus.init()

    # Container specific init
    case container_type do
      "all" ->
        Sanbase.Application.Web.init()
        Sanbase.Application.Scrapers.init()
        Sanbase.Application.Alerts.init()

      "web" ->
        Sanbase.Application.Web.init()

      "signals" ->
        Sanbase.Application.Alerts.init()

      "scrapers" ->
        Sanbase.Application.Scrapers.init()

      _ ->
        Sanbase.Application.Web.init()
    end
  end

  def print_starting_log(container_type) do
    case container_type do
      "all" ->
        Logger.info("Starting all Sanbase container types.")

      "web" ->
        Logger.info("Starting Web Sanbase.")

      "scrapers" ->
        Logger.info("Starting Scrapers Sanbase.")

      type when type in ["alerts", "signals"] ->
        Logger.info("Starting Alerts Sanbase.")

      unknown ->
        Logger.warn("Unkwnown type #{inspect(unknown)}. Starting a default web container.")
        Logger.info("Starting Web Sanbase.")
    end
  end

  def children_opts(container_type) do
    case container_type do
      "all" ->
        {web_children, _} = Sanbase.Application.Web.children()
        {scrapers_children, _} = Sanbase.Application.Scrapers.children()
        {alerts_children, _} = Sanbase.Application.Alerts.children()

        children = web_children ++ scrapers_children ++ alerts_children
        children = children |> Enum.uniq()

        opts = [
          strategy: :one_for_one,
          name: Sanbase.Supervisor,
          max_restarts: 5,
          max_seconds: 1
        ]

        {children, opts}

      "web" ->
        Sanbase.Application.Web.children()

      "scrapers" ->
        Sanbase.Application.Scrapers.children()

      type when type in ["alerts", "signals"] ->
        Sanbase.Application.Alerts.children()

      _unknown ->
        Sanbase.Application.Web.children()
    end
  end

  @doc ~s"""
  Some services must be started before all others. This should be a separate step
  as the `all` containers type will merge all the different children and some that
  must be in the front will end up in the middle.
  """
  def prepended_children(container_type) do
    [
      start_in(
        %{
          id: :sanbase_brod_sup_id,
          start: {:brod_sup, :start_link, []},
          type: :supervisor
        },
        [:dev, :prod]
      ),

      # SanExporterEx is the module that handles the data pushing to Kafka. As other
      # parts can be started that also require :brod_sup, :brod_sup will be started
      # separately and `start_brod_supervisor: false` is provided to
      # SanExporterEx
      {SanExporterEx,
       [
         kafka_producer_module: Config.module_get!(Sanbase.KafkaExporter, :supervisor),
         kafka_endpoint: kafka_endpoint(),
         start_brod_supervisor: false
       ]},

      # API Calls exporter is started only in `web` and `all` pods.
      start_if(
        fn ->
          Sanbase.KafkaExporter.child_spec(
            id: :api_call_exporter,
            name: :api_call_exporter,
            topic: Config.module_get!(Sanbase.KafkaExporter, :api_call_data_topic)
          )
        end,
        fn -> container_type in ["all", "web"] end
      ),

      # Prices exporter is started only in `scrapers` and `all` pods.
      start_if(
        fn ->
          Sanbase.KafkaExporter.child_spec(
            id: :prices_exporter,
            name: :prices_exporter,
            topic: Config.module_get!(Sanbase.KafkaExporter, :prices_topic),
            buffering_max_messages: 5_000,
            can_send_after_interval: 250,
            kafka_flush_timeout: 1000
          )
        end,
        fn -> container_type in ["all", "scrapers"] end
      ),

      # Kafka exporter for the Event Bus events
      Sanbase.KafkaExporter.child_spec(
        id: :sanbase_event_bus_kafka_exporter,
        name: :sanbase_event_bus_kafka_exporter,
        topic: Config.module_get!(KafkaExporterSubscriber, :event_bus_topic),
        kafka_flush_timeout:
          Config.module_get_integer!(KafkaExporterSubscriber, :kafka_flush_timeout),
        buffering_max_messages:
          Config.module_get_integer!(KafkaExporterSubscriber, :buffering_max_messages),
        can_send_after_interval:
          Config.module_get_integer!(KafkaExporterSubscriber, :can_send_after_interval)
      )
    ]
  end

  @doc ~s"""
  Children common for all types of container types
  """
  @spec common_children() :: [:supervisor.child_spec() | {module(), term()} | module()]
  def common_children() do
    [
      # Start the PubSub
      {Phoenix.PubSub, name: Sanbase.PubSub},

      # Start the Presence
      SanbaseWeb.Presence,

      # Start the endpoint when the application starts
      SanbaseWeb.Endpoint,

      # Start the Postgres Ecto repository
      Sanbase.Repo,

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
      Sanbase.Prices.Store,

      # Start the Task Supervisor
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

      # Mutex for forcing sequential execution when updating api call limits
      Supervisor.child_spec(
        {Mutex, name: Sanbase.ApiCallLimitMutex},
        id: Sanbase.ApiCallLimitMutex
      ),

      # Start telegram rate limiter. Used both in web and alerts
      Sanbase.ExternalServices.RateLimiting.Server.child_spec(
        :telegram_bot_rate_limiting_server,
        scale: 1000,
        limit: 30,
        time_between_requests: 10
      ),

      # General purpose cache available in all types
      {Sanbase.Cache,
       [
         id: :sanbase_generic_cache,
         name: Sanbase.Cache.name(),
         ttl_check_interval: :timer.seconds(30),
         global_ttl: :timer.minutes(5),
         acquire_lock_timeout: 30_000
       ]},

      # Service for fast checking if a slug is valid
      # `:available_slugs_module` option changes the module
      # used in test env to another one, this one is unused
      start_in(Sanbase.AvailableSlugs, [:dev, :prod]),

      # Process that starts test-only deps
      start_in(Sanbase.TestSetupService, [:test])
    ] ++
      Sanbase.EventBus.children()
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp kafka_endpoint() do
    url = Config.module_get!(Sanbase.Kafka, :kafka_url) |> to_charlist()
    port = Config.module_get_integer!(Sanbase.Kafka, :kafka_port)

    [{url, port}]
  end
end
