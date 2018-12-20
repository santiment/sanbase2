defmodule Sanbase.Application.Workers do
  import Sanbase.ApplicationUtils

  def init(), do: :ok

  @doc ~s"""
  Return the children and options that will be started in the workers container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children do
    children = [
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
