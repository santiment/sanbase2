defmodule Sanbase.Application do
  use Application
  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    if Code.ensure_loaded?(Envy) do
      Envy.auto_load()
    end

    {children, opts} =
      case System.get_env("CONTAINER_TYPE") || "all" do
        "web" ->
          Logger.info("Starting WEB Sanbase.")
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

    # Add error tracking through sentry
    :ok = :error_logger.add_report_handler(Sentry.Logger)

    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
