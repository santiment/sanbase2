defmodule Sanbase.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    Faktory.Configuration.init

    # Define workers and child supervisors to be supervised
    children = [
      # Start the Ecto repository
      supervisor(Sanbase.Repo, []),

      # Start the endpoint when the application starts
      supervisor(SanbaseWeb.Endpoint, []),

      # Time series DB connection
      Sanbase.Prices.Store.child_spec,

      # Time series DB connection
      Sanbase.Github.Store.child_spec,

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
        limit: 20,
        time_between_requests: 2000
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
        limit: 20,
        time_between_requests: 2000
      ),

      # Price fetcher
      Sanbase.ExternalServices.Coinmarketcap.child_spec(%{}),

      # Current marketcap fetcher
      Sanbase.ExternalServices.Coinmarketcap.TickerFetcher.child_spec(%{}),

      # Etherscan wallet tracking worker
      Sanbase.ExternalServices.Etherscan.Worker.child_spec(%{}),

      supervisor(Faktory.Supervisor, []),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sanbase.Supervisor, max_restarts: 5, max_seconds: 1]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    SanbaseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
