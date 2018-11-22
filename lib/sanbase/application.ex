defmodule Sanbase.Application do
  use Application
  require Logger

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
          Sanbase.Application.WebSupervisor.children()

        "scrapers" ->
          Logger.info("Starting Scrapers Sanbase.")
          Sanbase.Application.ScrapersSupervisor.children()

        "workers" ->
          Logger.info("Starting Workers Sanbase.")
          Sanbase.Application.WorkersSupervisor.children()

        "all" ->
          Logger.info("Start all Sanbase container types.")
          {web_children, _} = Sanbase.Application.WebSupervisor.children()
          {scrapers_children, _} = Sanbase.Application.ScrapersSupervisor.children()
          {workers_children, _} = Sanbase.Application.WorkersSupervisor.children()

          children = web_children ++ scrapers_children ++ workers_children
          children = children |> Enum.uniq()

          opts = [
            strategy: :one_for_one,
            name: Sanbase.Supervisor,
            max_restarts: 5,
            max_seconds: 1
          ]

          {children, opts}
      end

    children = (common_children() ++ children) |> Sanbase.ApplicationUtils.normalize_children()

    # Add error tracking through sentry
    :ok = :error_logger.add_report_handler(Sentry.Logger)

    Supervisor.start_link(children, opts)
  end

  def init(container_type) do
    # Common inits

    # Prometheus related
    Sanbase.Prometheus.EctoInstrumenter.setup()

    Sanbase.Prometheus.PipelineInstrumenter.setup()

    Sanbase.Prometheus.Exporter.setup()

    # Container specific init
    case container_type do
      "all" ->
        Sanbase.Application.WebSupervisor.init()
        Sanbase.Application.ScrapersSupervisor.init()
        Sanbase.Application.WorkersSupervisor.init()

      "web" ->
        Sanbase.Application.WebSupervisor.init()

      "scrapers" ->
        Sanbase.Application.ScrapersSupervisor.init()

      "workers" ->
        Sanbase.Application.WorkersSupervisor.init()
    end
  end

  @doc ~s"""
  Children common for all types of container types
  """
  def common_children() do
    [
      # Start the endpoint when the application starts
      SanbaseWeb.Endpoint,

      # Start the Postgres Ecto repository
      Sanbase.Repo,

      # Time series Prices DB connection
      Sanbase.Prices.Store.child_spec()
    ]
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def start_faktory?() do
    System.get_env("FAKTORY_HOST") && :ets.whereis(Faktory.Configuration) == :undefined
  end

  def faktory() do
    import Supervisor.Spec

    Faktory.Configuration.init()
    supervisor(Faktory.Supervisor, [])
  end
end
