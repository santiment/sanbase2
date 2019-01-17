defmodule Sanbase.Application.Signals do
  import Sanbase.ApplicationUtils

  def init(), do: :ok

  @doc ~s"""
  Return the children and options that will be started in the scrapers container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    children = [
      # Start the TimescaleDB Ecto repository
      Sanbase.TimescaleRepo,

      # Start the Clickhouse Repo
      start_in({Sanbase.ClickhouseRepo, []}, [:dev, :prod]),

      # Start signals cache
      Supervisor.child_spec(
        {ConCache,
         [
           name: :signals_cache,
           ttl_check_interval: :timer.minutes(10),
           global_ttl: :timer.hours(1)
         ]},
        id: :con_cache_signals
      ),

      # Quantum Scheduler
      start_if(
        fn -> {Sanbase.Scheduler, []} end,
        fn -> System.get_env("QUANTUM_SCHEDULER_ENABLED") end
      )
    ]

    opts = [
      strategy: :one_for_one,
      name: Sanbase.SignalsSupervisor,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
