defmodule Sanbase.Application.Alerts do
  import Sanbase.ApplicationUtils

  def init(), do: :ok

  @doc ~s"""
  Return the children and options that will be started in the scrapers container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    children = [
      # Mutex used when sending notifications for triggered alerts
      # Guards agains concurrently sending notifications to a single user
      # which can bypass the limit for alerts per day
      Supervisor.child_spec(
        {Mutex, name: Sanbase.AlertMutex},
        id: Sanbase.AlertMutex
      ),

      # Start the alert evaluator cache
      {Sanbase.Cache,
       [
         id: :alerts_evaluator_cache,
         name: :alerts_evaluator_cache,
         ttl_check_interval: :timer.seconds(15),
         global_ttl: :timer.minutes(5),
         acquire_lock_timeout: 120_000
       ]},

      # Quantum Scheduler
      start_if(
        fn -> {Sanbase.Alerts.Scheduler, []} end,
        fn -> Sanbase.Alerts.Scheduler.enabled?() end
      )
    ]

    opts = [
      name: Sanbase.AlertsSupervisor,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end
end
