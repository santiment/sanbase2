defmodule Sanbase.Application.WebSupervisor do
  import Sanbase.ApplicationUtils

  def children() do
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

      # Rate limit API calls
      {PlugAttack.Storage.Ets,
       [
         name: SanbaseWeb.Graphql.PlugAttack.Storage,
         clean_period: 60_000
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

    opts = [strategy: :one_for_one, name: Sanbase.WebSupervisor, max_restarts: 5, max_seconds: 1]

    {children, opts}
  end
end
