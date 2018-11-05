defmodule Sanbase.Application.WorkersSupervisor do
  import Sanbase.ApplicationUtils

  def children do
    children = [
      # Start the Postgres Ecto repository
      Sanbase.Repo,

      # Start the endpoint when the application starts. Used for healtchecks
      SanbaseWeb.Endpoint,

      # Time series Prices DB connection
      Sanbase.Prices.Store.child_spec(),

      # Time series Github DB connection
      Sanbase.Github.Store.child_spec(),

      # Start the Faktory Supervisor
      start_if(
        &Sanbase.Application.faktory/0,
        &Sanbase.Application.start_faktory?/0
      )
    ]

    opts = [
      strategy: :one_for_one,
      name: Sanbase.WorkersSupervisor,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
