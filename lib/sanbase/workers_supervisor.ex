defmodule Sanbase.Application.WorkersSupervisor do
  use Application

  import Sanbase.ApplicationUtils

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    if Code.ensure_loaded?(Envy) do
      Envy.auto_load()
    end

    # Define workers and child supervisors to be supervised
    children =
      [
        # Time series Github DB connection
        Sanbase.Github.Store.child_spec()
      ] ++
        faktory_supervisor() ++
        [
          # Github activity scraping scheduler
          Sanbase.ExternalServices.Github.child_spec(%{})
        ]

    children = children |> normalize_children()

    opts = [
      strategy: :one_for_one,
      name: Sanbase.WorkersSupervisor,
      max_restarts: 5,
      max_seconds: 1
    ]

    # Add error tracking through sentry
    :ok = :error_logger.add_report_handler(Sentry.Logger)

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp faktory_supervisor do
    if System.get_env("FAKTORY_HOST") do
      Faktory.Configuration.init()
      [{Faktory.Supervisor, []}]
    else
      []
    end
  end
end
