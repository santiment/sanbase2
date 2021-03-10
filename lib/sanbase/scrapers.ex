defmodule Sanbase.Application.Scrapers do
  import Sanbase.ApplicationUtils

  alias Sanbase.ExternalServices.RateLimiting
  def init(), do: :ok

  @doc ~s"""
  Return the children and options that will be started in the scrapers container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    children = [
      # Start a Registry
      {Registry, keys: :unique, name: Sanbase.Registry},

      # Time sereies Twitter DB connection
      Sanbase.Twitter.Store.child_spec(),

      # Etherscan rate limiter
      RateLimiting.Server.child_spec(
        :etherscan_rate_limiter,
        scale: 1000,
        limit: 5,
        time_between_requests: 100
      ),

      # Coinmarketcap graph data rate limiter
      RateLimiting.Server.child_spec(
        :graph_coinmarketcap_rate_limiter,
        scale: 60_000,
        limit: 60,
        time_between_requests: 100
      ),

      # Coinmarketcap api rate limiter
      RateLimiting.Server.child_spec(
        :api_coinmarketcap_rate_limiter,
        scale: 60_000,
        limit: 5,
        time_between_requests: 2000
      ),

      # Coinmarketcap http rate limiter
      RateLimiting.Server.child_spec(
        :http_coinmarketcap_rate_limiter,
        scale: 60_000,
        limit: 30,
        time_between_requests: 1000
      ),

      # Twitter API rate limiter
      RateLimiting.Server.child_spec(
        :twitter_api_rate_limiter,
        scale: 60 * 15 * 1000,
        limit: 450,
        time_between_requests: 10
      ),

      # Price fetcher
      Sanbase.ExternalServices.Coinmarketcap,

      # Current marketcap fetcher
      Sanbase.ExternalServices.Coinmarketcap.TickerFetcher,

      # Twitter account data tracking worker
      Sanbase.Twitter.Worker,

      # Quantum Scheduler
      start_if(
        fn -> {Sanbase.Scrapers.Scheduler, []} end,
        fn -> Sanbase.Scrapers.Scheduler.enabled?() end
      )
    ]

    opts = [
      name: Sanbase.ScrapersSupervisor,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
