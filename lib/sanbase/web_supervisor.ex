defmodule Sanbase.Application.WebSupervisor do
  use Application

  import Sanbase.ApplicationUtils

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    if Code.ensure_loaded?(Envy) do
      Envy.auto_load()
    end

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Postgres Ecto repository
      Sanbase.Repo,

      # Start the TimescaleDB Ecto repository
      Sanbase.TimescaleRepo,

      # Start the endpoint when the application starts
      SanbaseWeb.Endpoint,

      # Start the Clickhouse Repo
      start_in({Sanbase.ClickhouseRepo, []}, [:prod]),

      # Start the Elasticsearch Cluster connection
      Sanbase.Elasticsearch.Cluster,

      # Start the graphQL in-memory cache
      {ConCache,
       [
         name: :graphql_cache,
         ttl_check_interval: :timer.minutes(1),
         global_ttl: :timer.minutes(5),
         acquire_lock_timeout: 30_000
       ]},

      # Time series Prices DB connection
      Sanbase.Prices.Store.child_spec(),

      # Time sereies TwitterData DB connection
      Sanbase.ExternalServices.TwitterData.Store.child_spec(),

      # Time series Github DB connection
      Sanbase.Github.Store.child_spec(),

      # Transform a list of transactions into a list of transactions
      # where addresses are marked whether or not they are an exchange address
      Sanbase.Clickhouse.MarkExchanges.child_spec(%{})
    ]

    children = children |> normalize_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sanbase.WebSupervisor, max_restarts: 5, max_seconds: 1]

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
end
