defmodule Sanbase.Application do
  use Application

  import Sanbase.ApplicationUtils

  require Logger
  alias Sanbase.Utils.Config

  alias Sanbase.EventBus.KafkaExporterSubscriber

  def start(_type, _args) do
    # .env files are loaded in config/runtime.exs via Sanbase.EnvConfigLoader.auto_load/0

    # Container type is one of: web, scrapers, signals, all
    container_type = container_type()

    print_starting_log(container_type)

    # Increase the backtrace depth, start the event bus, etc.
    init(container_type)

    # Get the proper children that have to be started in the current container type
    {children, opts} = children_opts(container_type)

    # Some children must start before others. `all` combines every other container type,
    # so these are prepended explicitly or they end up mid-list.
    prepended_children = prepended_children(container_type)

    # Children common to all container types: Ecto adapters, Telemetry, Endpoint, etc.
    common_children = common_children()

    # `start_in`/`start_if` return `nil` for a child that is not started - clean those out.
    children =
      (prepended_children ++ common_children ++ children)
      |> Sanbase.ApplicationUtils.normalize_children()
      |> Enum.uniq()

    :logger.add_handler(:sanbase_sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    # Redact Absinthe/Ecto log lines for users with NDA-protected activity.
    Sanbase.Logger.MaybeHideActivityTraces.install!()

    case Supervisor.start_link(children, opts) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Logger.error(Exception.format_exit(reason))
        {:error, reason}
    end
  end

  def init(container_type) do
    # Set here, not in the phoenix config, so it applies to non-phoenix work too.
    :erlang.system_flag(:backtrace_depth, 20)

    Sanbase.EventBus.init()

    # Container specific init
    case container_type do
      "all" ->
        Sanbase.Application.Web.init()
        Sanbase.Application.Scrapers.init()
        Sanbase.Application.Alerts.init()
        Sanbase.Application.Queries.init()
        Sanbase.Application.Mcp.init()

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

      "mcp" ->
        Sanbase.Application.Mcp.init()

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

      "mcp" ->
        Logger.info("Starting MCP Sanbase.")

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
        {queries_children, _} = Sanbase.Application.Queries.children()
        {mcp_children, _} = Sanbase.Application.Mcp.children()

        children =
          web_children ++
            scrapers_children ++
            alerts_children ++ admin_children ++ queries_children ++ mcp_children

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

      "mcp" ->
        Sanbase.Application.Mcp.children()

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
      Sanbase.Logger.ActivityTracesFilterWatchdog,

      # Telemetry metrics
      SanbaseWeb.Telemetry,

      # Prometheus metrics
      SanbaseWeb.Prometheus,
      Sanbase.Repo,

      # The main ClickhouseRepo, needed by every pod.
      start_in_and_if(
        fn -> Sanbase.ClickhouseRepo end,
        [:dev, :prod],
        fn -> Sanbase.ClickhouseRepo.enabled?() end
      ),
      clickhouse_readonly_children,
      clickhouse_readonly_per_plan_children,
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

      # Deep research runners keep a run alive across LiveView disconnects.
      {Registry, [keys: :unique, name: Sanbase.DeepResearch.Registry]},
      {DynamicSupervisor, [name: Sanbase.DeepResearch.RunnerSupervisor, strategy: :one_for_one]},
      Sanbase.ApiCallLimit.ETS,

      # Hammer rate limiter backend (ETS)
      {Sanbase.RateLimit, [clean_period: :timer.minutes(10), key_older_than: :timer.hours(4)]},

      # Telegram rate limiter, used both in web and alerts
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
         # Must exceed the ClickHouse budget bounding the lock holder (85s).
         # See docs/timeouts.md.
         acquire_lock_timeout: 102_000
       ]},

      # GraphQL in-memory cache
      start_if(
        fn ->
          SanbaseWeb.Graphql.Cache.child_spec(
            id: :graphql_api_cache,
            name: :graphql_cache
          )
        end,
        fn -> container_type() in ["web", "all"] end
      ),

      # Log GraphQL cache stats and sweep the oldest entries past max_payload_mb()
      start_if(
        fn -> SanbaseWeb.Graphql.CacheMonitor end,
        fn -> container_type() in ["web", "all"] end
      ),

      # Per-pod BEAM/OS memory stats, shown at /admin/memory_stats
      start_if(
        fn -> Sanbase.Monitoring.MemoryCollector end,
        fn -> Sanbase.Monitoring.MemoryCollector.enabled?() end
      ),

      # Fast slug validity check. `:available_slugs_module` swaps the module in tests.
      start_in(Sanbase.AvailableSlugs, [:dev, :prod]),
      {Phoenix.PubSub, name: Sanbase.PubSub},
      SanbaseWeb.Presence,
      SanbaseWeb.Endpoint,

      # Drain running connections so executing API calls finish: the acceptor stops taking
      # new connections, then waits for the rest, up to 30 seconds.
      {SanbaseWeb.ConnectionDrainer, shutdown: 30_000, ranch_ref: SanbaseWeb.Endpoint.HTTP},

      # Process that starts test-only deps
      start_in(Sanbase.TestSetupService, [:test]),
      Sanbase.EventBus.children()
    ]
    |> List.flatten()
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
