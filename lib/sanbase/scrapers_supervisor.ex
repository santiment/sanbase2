defmodule Sanbase.Application.ScrapersSupervisor do
  import Sanbase.ApplicationUtils

  def children() do
    children =
      [
        # Start the endpoint when the application starts. Used for healtchecks
        SanbaseWeb.Endpoint,

        # Start the Task Supervisor
        {Task.Supervisor, [name: Sanbase.TaskSupervisor]},

        # Start the Postgres Ecto repository
        Sanbase.Repo,

        # Start a Registry
        {Registry, keys: :unique, name: Sanbase.Registry},

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

        # Price fetcher
        Sanbase.ExternalServices.Coinmarketcap2.child_spec(%{}),

        # Current marketcap fetcher
        # TODO: Change after switching over to only this cmc
        Sanbase.ExternalServices.Coinmarketcap.TickerFetcher.child_spec(%{}),
        Sanbase.ExternalServices.Coinmarketcap.TickerFetcher2.child_spec(%{}),

        # Twitter account data tracking worker
        Sanbase.ExternalServices.TwitterData.Worker.child_spec(%{}),

        # Twitter account historical data
        Sanbase.ExternalServices.TwitterData.HistoricalData.child_spec(%{})
      ] ++
        Sanbase.Application.faktory_supervisor() ++
        [
          # Github activity scraping scheduler
          Sanbase.ExternalServices.Github.child_spec(%{})
        ]

    children = children |> normalize_children()

    opts = [
      strategy: :one_for_one,
      name: Sanbase.ScrapersSupervisor,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
