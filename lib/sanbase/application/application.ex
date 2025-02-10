defmodule Sanbase.Application do
  @moduledoc false
  use Application

  import Sanbase.ApplicationUtils

  alias Sanbase.Application.Admin
  alias Sanbase.Application.Alerts
  alias Sanbase.Application.Queries
  alias Sanbase.Application.Scrapers
  alias Sanbase.Application.Web
  alias Sanbase.EventBus.KafkaExporterSubscriber
  alias Sanbase.Utils.Config

  require Logger

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

    # Combine all the children to be started. Run a normalization. This normalization
    # takes care of the results of some custom `start_in` and `start_if` custom cases.
    # They might return `nil` to signal that they don't have to be started and these
    # values need to be cleaned.
    children =
      (prepended_children ++ common_children ++ children)
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
        Web.init()
        Scrapers.init()
        Alerts.init()

      "admin" ->
        Admin.init()

      "web" ->
        Web.init()

      "signals" ->
        Alerts.init()

      "scrapers" ->
        Scrapers.init()

      "queries" ->
        Queries.init()

      _ ->
        Web.init()
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
        {web_children, _} = Web.children()
        {scrapers_children, _} = Scrapers.children()
        {alerts_children, _} = Alerts.children()
        {admin_children, _} = Admin.children()
        {queries_children, _} = Admin.children()

        children =
          web_children ++
            scrapers_children ++ alerts_children ++ admin_children ++ queries_children

        children = Enum.uniq(children)

        opts = [
          strategy: :one_for_one,
          name: Sanbase.Supervisor,
          max_restarts: 5,
          max_seconds: 1
        ]

        {children, opts}

      "admin" ->
        Admin.children()

      "web" ->
        Web.children()

      "scrapers" ->
        Scrapers.children()

      "queries" ->
        Queries.children()

      type when type in ["alerts", "signals"] ->
        Alerts.children()

      _unknown ->
        Web.children()
    end
  end

  @doc ~s"""
  Some services must be started before all others. This should be a separate step
  as the `all` containers type will merge all the different children and some that
  must be in the front will end up in the middle.
  """
  def prepended_children(container_type) do
    [
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
        kafka_flush_timeout: Config.module_get_integer!(KafkaExporterSubscriber, :kafka_flush_timeout),
        buffering_max_messages: Config.module_get_integer!(KafkaExporterSubscriber, :buffering_max_messages),
        can_send_after_interval: Config.module_get_integer!(KafkaExporterSubscriber, :can_send_after_interval)
      )
    ]
  end

  @doc ~s"""
  Children common for all types of container types
  """
  @spec common_children() :: [:supervisor.child_spec() | {module(), term()} | module()]
  def common_children do
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

    List.flatten([
      SanbaseWeb.Telemetry,
      SanbaseWeb.Prometheus,
      Sanbase.Repo,
      start_in_and_if(fn -> Sanbase.ClickhouseRepo end, [:dev, :prod], fn -> Sanbase.ClickhouseRepo.enabled?() end),
      clickhouse_readonly_children,
      clickhouse_readonly_per_plan_children,
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]},
      Sanbase.ApiCallLimit.ETS,
      Sanbase.ExternalServices.RateLimiting.Server.child_spec(:telegram_bot_rate_limiting_server,
        scale: 1000,
        limit: 30,
        time_between_requests: 10
      ),
      {Sanbase.Cache,
       [
         id: :sanbase_generic_cache,
         name: Sanbase.Cache.name(),
         ttl_check_interval: :timer.seconds(30),
         global_ttl: :timer.minutes(5),
         acquire_lock_timeout: 60_000
       ]},
      start_in(Sanbase.AvailableSlugs, [:dev, :prod]),
      {Phoenix.PubSub, name: Sanbase.PubSub},
      SanbaseWeb.Presence,
      SanbaseWeb.Endpoint,
      start_in(Sanbase.TestSetupService, [:test]),
      Sanbase.EventBus.children()
    ])

    # Telemetry metrics

    # Prometheus metrics

    # Start the Postgres Ecto repository

    # Start the main ClickhouseRepo. This is started in all
    # pods as each pod will need it.

    # Start the main clickhouse read-only repos

    # Start the clickhouse read-only repos for different plans

    # Start the Task Supervisor

    # Star the API call service

    # Start telegram rate limiter. Used both in web and alerts

    # General purpose cache available in all types

    # Service for fast checking if a slug is valid
    # `:available_slugs_module` option changes the module
    # used in test env to another one, this one is unused

    # Start the PubSub

    # Start the Presence

    # Start the endpoint when the application starts

    # Process that starts test-only deps
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
