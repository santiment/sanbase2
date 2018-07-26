defmodule Sanbase.Application do
  use Application
  import Supervisor.Spec

  import Supervisor.Spec
  import Sanbase.ApplicationUtils

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    if Code.ensure_loaded?(Envy) do
      Envy.auto_load()
    end

    Faktory.Configuration.init

    # Define workers and child supervisors to be supervised
    children =
      [
        # Start the Task Supervisor
        {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

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

        # Start a Registry
        {Registry, keys: :unique, name: Sanbase.Registry},

        # Start the graphQL in-memory cache
        {ConCache,
         [
           name: :graphql_cache,
           ttl_check_interval: :timer.minutes(1),
           global_ttl: :timer.minutes(5),
           acquire_lock_timeout: 30_000
         ]},

        # Start the Clickhouse Repo
        {Sanbase.ClickhouseRepo, []},

        # Start a Registry
        {Registry, keys: :unique, name: Sanbase.Registry},

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

        # Etherscan rate limiter
        Sanbase.ExternalServices.RateLimiting.Server.child_spec(
          :etherscan_rate_limiter,
          scale: 1000,
          limit: 5,
          time_between_requests: 100
        ),

        # Coinmarketcap graph data rate limiter
        Sanbase.ExternalServices.RateLimiting.Server.child_spec(
          :graph_coinmarketcap_rate_limiter,
          scale: 60_000,
          limit: 30,
          time_between_requests: 1000
        ),

        # Coinmarketcap api rate limiter
        Sanbase.ExternalServices.RateLimiting.Server.child_spec(
          :api_coinmarketcap_rate_limiter,
          scale: 60_000,
          limit: 5,
          time_between_requests: 2000
        ),

        # Coinmarketcap http rate limiter
        Sanbase.ExternalServices.RateLimiting.Server.child_spec(
          :http_coinmarketcap_rate_limiter,
          scale: 60_000,
          limit: 30,
          time_between_requests: 1000
        ),

        # Twitter API rate limiter
        Sanbase.ExternalServices.RateLimiting.Server.child_spec(
          :twitter_api_rate_limiter,
          scale: 60 * 15 * 1000,
          limit: 450,
          time_between_requests: 10
        ),

        # Twittercounter API rate limiter
        Sanbase.ExternalServices.RateLimiting.Server.child_spec(
          :twittercounter_api_rate_limiter,
          scale: 60 * 60 * 1000,
          limit: 100,
          time_between_requests: 100
        ),
        worker(PlugAttack.Storage.Ets, [
          SanbaseWeb.Graphql.PlugAttack.Storage,
          [clean_period: 60_000]
        ]),

        # Price fetcher
        # TODO: Change after switching over to only this cmc
        Sanbase.ExternalServices.Coinmarketcap.child_spec(%{}),
        Sanbase.ExternalServices.Coinmarketcap2.child_spec(%{}),

        # Current marketcap fetcher
        # TODO: Change after switching over to only this cmc
        Sanbase.ExternalServices.Coinmarketcap.TickerFetcher.child_spec(%{}),
        Sanbase.ExternalServices.Coinmarketcap.TickerFetcher2.child_spec(%{}),

        # Twitter account data tracking worker
        Sanbase.ExternalServices.TwitterData.Worker.child_spec(%{}),

        # Twitter account historical data
        Sanbase.ExternalServices.TwitterData.HistoricalData.child_spec(%{}),

        # Transform a list of transactions into a list of transactions
        # where addresses are marked whether or not they are an exchange address
        Sanbase.Clickhouse.MarkExchanges.child_spec(%{})
      ] ++
        faktory_supervisor() ++
        [
          # Github activity scraping scheduler
          Sanbase.ExternalServices.Github.child_spec(%{})
        ]

    children = children |> normalize_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sanbase.Supervisor, max_restarts: 5, max_seconds: 1]

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
      [supervisor(Faktory.Supervisor, [])]
    else
      []
    end
  end
end
