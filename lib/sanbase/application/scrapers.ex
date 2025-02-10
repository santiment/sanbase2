defmodule Sanbase.Application.Scrapers do
  @moduledoc false
  import Sanbase.ApplicationUtils

  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.Scrapers.Scheduler

  def init, do: :ok

  @doc ~s"""
  Return the children and options that will be started in the scrapers container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children do
    children = [
      # Start a Registry
      {Registry, keys: :unique, name: Sanbase.Registry},

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

      # Price validator for the coinmarketcap prices
      Sanbase.Price.Validator,

      # Historical coinmarketcap price fetcher
      Sanbase.ExternalServices.Coinmarketcap,

      # Realtime coinmarketcap price fetcher
      Sanbase.ExternalServices.Coinmarketcap.TickerFetcher,

      # Oban for scraper jobs
      {Oban, oban_scrapers_config()},

      # Scrape and export Cryptocompare realtime and historical prices.
      # Historical prices work is scheduled by Oban
      Sanbase.Cryptocompare.Supervisor,

      # Twitter account data tracking worker
      Sanbase.Twitter.Worker,

      # Quantum Scheduler
      start_if(
        fn -> {Scheduler, []} end,
        fn -> Scheduler.enabled?() end
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

  defp oban_scrapers_config do
    config = Application.fetch_env!(:sanbase, Oban.Scrapers)

    # In case the DB config or URL is pointing to production, put the proper
    # schema in the config. This will be used both on prod and locally when
    # connecting to the stage DB. This is automated so when the stage DB is
    # used, the config should not be changed manually to include the schema
    if Sanbase.Utils.prod_db?() do
      Keyword.put(config, :prefix, "sanbase2")
    else
      config
    end
  end
end
