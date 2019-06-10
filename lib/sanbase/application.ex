defmodule Sanbase.Application do
  use Application
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

    prepended_children = prepended_children(container_type)

    children =
      (prepended_children ++ common_children() ++ children)
      |> Sanbase.ApplicationUtils.normalize_children()

    # Add error tracking through sentry
    {:ok, _} = Logger.add_backend(Sentry.LoggerBackend)
    Supervisor.start_link(children, opts)
  end

  @spec init(String.t()) :: :ok | [any()]
  def init(container_type) do
    # Common inits

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
  def prepended_children(container_type) when container_type in ["web", "all"] do
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
      {Sanbase.ApiCallDataExporter, [topic: kafka_api_call_data_topic()]}
    ]
  end

  def prepended_children(_), do: []

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

      # Time series Prices DB connection
      Sanbase.Prices.Store.child_spec(),

      # Start the Task Supervisor
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

      # Start telegram rate limiter. Used both in web and signals
      Sanbase.ExternalServices.RateLimiting.Server.child_spec(
        :telegram_bot_rate_limiting_server,
        scale: 1000,
        limit: 30,
        time_between_requests: 10
      )
    ]
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp kafka_producer_supervisor_module() do
    Config.module_get(Sanbase.ApiCallDataExporter, :supervisor, SanExporterEx.Producer.Supervisor)
  end

  defp kafka_api_call_data_topic() do
    Config.module_get(Sanbase.ApiCallDataExporter, :kafka_topic, "sanbase_api_call_data")
  end

  defp kafka_endpoint() do
    url = Config.module_get(Sanbase.ApiCallDataExporter, :kafka_url) |> to_charlist()

    port =
      Config.module_get(Sanbase.ApiCallDataExporter, :kafka_port) |> Sanbase.Math.to_integer()

    [{url, port}]
  end
end
