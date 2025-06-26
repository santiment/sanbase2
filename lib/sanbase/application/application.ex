defmodule Sanbase.Application do
  use Application

  import Sanbase.ApplicationUtils

  require Logger
  alias Sanbase.Utils.Config

  alias Sanbase.EventBus.KafkaExporterSubscriber

  def start(_type, _args) do
    Code.ensure_loaded?(Envy) && Envy.auto_load()

    # Container type is one of: web, scrapers, signals, all
    container_type = container_type()

    print_starting_log(container_type)

    # Do some initialization. This includes increasing the backtrace depth,
    # starting the event bus, etc.
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

    # Some children need to be started last
    # At the moment these are the Endpoint and the ConnectionDrainer. This way when the
    # application is stopped, we first stop the ConnectionDrainer which will drain
    # the connections and stop the acceptor pool. The Endpoint is also here, so the rest
    # of the services that are needed to process the remaining requests are still running --
    # DB connections, Caches, API Call Exporters, etc.
    last_children = last_children()

    # Combine all the children to be started. Run a normalization. This normalization
    # takes care of the results of some custom `start_in` and `start_if` custom cases.
    # They might return `nil` to signal that they don't have to be started and these
    # values need to be cleaned.
    children =
      (prepended_children ++ common_children ++ children ++ last_children)
      |> Sanbase.ApplicationUtils.normalize_children()
      |> Enum.uniq()

    :logger.add_handler(:sanbase_sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    case Supervisor.start_link(children, opts) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Logger.error(Exception.format_exit(reason))
        {:error, reason}
    end
  end

  def init(container_type) do
    # Increase the backtrace depth here and not in the phoenix config
    # so it applies to all non-phoenix work, too
    :erlang.system_flag(:backtrace_depth, 20)

    Sanbase.EventBus.init()

    # Container specific init
    case container_type do
      "all" ->
        Sanbase.Application.Web.init()
        Sanbase.Application.Scrapers.init()
        Sanbase.Application.Alerts.init()

      "admin" ->
        Sanbase.Application.Admin.init()

      "web" ->
        Sanbase.Application.Web.init()

      "signals" ->
        Sanbase.Application.Alerts.init()

      "scrapers" ->
        Sanbase.Application.Scrapers.init()

      "queries" ->
        Sanbase.Application.Queries.init()

      _ ->
        Sanbase.Application.Web.init()
    end
  end

  def print_starting_log(container_type) do
    case container_type do
      "all" ->
        Logger.info("Starting all Sanbase container types.")

      "admin" ->
        Logger.info("Starting Admin Sanbase.")

      "web" ->
        Logger.info("Starting Web Sanbase.")

      "scrapers" ->
        Logger.info("Starting Scrapers Sanbase.")

      "queries" ->
        Logger.configure(level: :debug)
        Logger.info("Starting Queries Sanbase.")

      type when type in ["alerts", "signals"] ->
        Logger.info("Starting Alerts Sanbase.")

      unknown ->
        Logger.warning("Unkwnown type #{inspect(unknown)}. Starting a default web container.")
        Logger.info("Starting Web Sanbase.")
    end
  end

  def children_opts(container_type) do
    case container_type do
      "all" ->
        {web_children, _} = Sanbase.Application.Web.children()
        {scrapers_children, _} = Sanbase.Application.Scrapers.children()
        {alerts_children, _} = Sanbase.Application.Alerts.children()
        {admin_children, _} = Sanbase.Application.Admin.children()
        {queries_children, _} = Sanbase.Application.Admin.children()

        children =
          web_children ++
            scrapers_children ++ alerts_children ++ admin_children ++ queries_children

        children = children |> Enum.uniq()

        opts = [
          strategy: :one_for_one,
          name: Sanbase.Supervisor,
          max_restarts: 5,
          max_seconds: 1
        ]

        {children, opts}

      "admin" ->
        Sanbase.Application.Admin.children()

      "web" ->
        Sanbase.Application.Web.children()

      "scrapers" ->
        Sanbase.Application.Scrapers.children()

      "queries" ->
        Sanbase.Application.Queries.children()

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
      # To enable the persistent term backend
      # https://hexdocs.pm/absinthe/overview.html
      {Absinthe.Schema, SanbaseWeb.Graphql.Schema},

      # Start (optionally) the Kafka Brod Supervisor
      start_in_and_if(
        fn ->
          %{
            id: :sanbase_brod_sup_id,
            start: {:brod_sup, :start_link, []},
            type: :supervisor
          }
        end,
        [:dev, :prod],
        fn ->
          System.get_env("REAL_KAFKA_ENABLED", "true") == "true"
        end
      ),

      # API Calls exporter is started only in `web` and `all` pods.
      start_if(
        fn ->
          Sanbase.KafkaExporter.child_spec(
            id: :api_call_exporter,
            name: :api_call_exporter,
            topic: Config.module_get!(Sanbase.KafkaExporter, :api_call_data_topic)
          )
        end,
        fn ->
          container_type in ["all", "web"]
        end
      ),

      # sanbase_user_intercom_attributes exporter is started only in `scrapers` and `all` pods.
      start_if(
        fn ->
          Sanbase.KafkaExporter.child_spec(
            id: :sanbase_user_intercom_attributes,
            name: :sanbase_user_intercom_attributes,
            topic: "sanbase_user_intercom_attributes",
            buffering_max_messages: 5_000,
            can_send_after_interval: 250,
            kafka_flush_timeout: 1000
          )
        end,
        fn -> container_type in ["all", "scrapers"] end
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
    clickhouse_readonly = [Sanbase.ClickhouseRepo.ReadOnly]

    clickhouse_readonly_per_plan = [
      Sanbase.ClickhouseRepo.FreeUser,
      Sanbase.ClickhouseRepo.SanbaseProUser,
      Sanbase.ClickhouseRepo.SanbaseMaxUser,
      Sanbase.ClickhouseRepo.BusinessProUser,
      Sanbase.ClickhouseRepo.BusinessMaxUser
    ]

    clickhouse_readonly_children =
      for repo <- clickhouse_readonly do
        start_in_and_if(
          fn -> repo end,
          [:dev, :prod],
          fn ->
            container_type() in ["web", "queries", "all"] and Sanbase.ClickhouseRepo.enabled?()
          end
        )
      end

    clickhouse_readonly_per_plan_children =
      for repo <- clickhouse_readonly_per_plan do
        start_in_and_if(
          fn -> repo end,
          [:dev, :prod],
          fn -> container_type() in ["web", "all"] and Sanbase.ClickhouseRepo.enabled?() end
        )
      end

    [
      # Telemetry metrics
      SanbaseWeb.Telemetry,

      # Prometheus metrics
      SanbaseWeb.Prometheus,

      # Start the Postgres Ecto repository
      Sanbase.Repo,

      # Start the main ClickhouseRepo. This is started in all
      # pods as each pod will need it.
      start_in_and_if(
        fn -> Sanbase.ClickhouseRepo end,
        [:dev, :prod],
        fn -> Sanbase.ClickhouseRepo.enabled?() end
      ),

      # Start the main clickhouse read-only repos
      clickhouse_readonly_children,

      # Start the clickhouse read-only repos for different plans
      clickhouse_readonly_per_plan_children,

      # Start the Task Supervisor
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

      # Star the API call service
      Sanbase.ApiCallLimit.ETS,

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
         acquire_lock_timeout: 60_000
       ]},

      # Service for fast checking if a slug is valid
      # `:available_slugs_module` option changes the module
      # used in test env to another one, this one is unused
      start_in(Sanbase.AvailableSlugs, [:dev, :prod]),

      # Start the PubSub
      {Phoenix.PubSub, name: Sanbase.PubSub},

      # Start the Presence
      SanbaseWeb.Presence,

      # Process that starts test-only deps
      start_in(Sanbase.TestSetupService, [:test]),
      Sanbase.EventBus.children()
    ]
    |> List.flatten()
  end

  def last_children() do
    # Start the endpoint when the application starts
    [
      SanbaseWeb.Endpoint,

      # Drain the running connections before closing. This will allow the
      # currently executing API calls to finish. The drainer first makes
      # the TCP acceptor to stop accepting new connections and then waits
      # until there are no connections or 30 seconds pass.
      {SanbaseWeb.ConnectionDrainer, shutdown: 30_000, ranch_ref: SanbaseWeb.Endpoint.HTTP}
    ]
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
