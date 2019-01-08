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
          Sanbase.Application.Web.children()

        "scrapers" ->
          Logger.info("Starting Scrapers Sanbase.")
          Sanbase.Application.Scrapers.children()

        "workers" ->
          Logger.info("Starting Workers Sanbase.")
          Sanbase.Application.Workers.children()

        "signals" ->
          Logger.info("Starting Signals Sanbase.")
          Sanbase.Application.Signals.children()

        "all" ->
          Logger.info("Start all Sanbase container types.")
          {web_children, _} = Sanbase.Application.Web.children()
          {scrapers_children, _} = Sanbase.Application.Scrapers.children()
          {workers_children, _} = Sanbase.Application.Workers.children()

          children = web_children ++ scrapers_children ++ workers_children
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
        Sanbase.Application.Web.init()
        Sanbase.Application.Scrapers.init()
        Sanbase.Application.Workers.init()
        Sanbase.Application.Signals.init()

      "web" ->
        Sanbase.Application.Web.init()

      "signals" ->
        Sanbase.Application.Signals.init()

      "scrapers" ->
        Sanbase.Application.Scrapers.init()

      "workers" ->
        Sanbase.Application.Workers.init()

      _ ->
        Sanbase.Application.Web.init()
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
      Sanbase.Prices.Store.child_spec(),

      # Start the Task Supervisor
      {Task.Supervisor, [name: Sanbase.TaskSupervisor]}
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
