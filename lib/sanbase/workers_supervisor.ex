defmodule Sanbase.Application.WorkersSupervisor do
  def children do
    children =
      [
        # Time series Github DB connection
        Sanbase.Github.Store.child_spec()
      ] ++
        faktory_supervisor() ++
        [
          # Github activity scraping scheduler
          Sanbase.ExternalServices.Github.child_spec(%{})
        ]

    opts = [
      strategy: :one_for_one,
      name: Sanbase.WorkersSupervisor,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end

  defp faktory_supervisor do
    if System.get_env("FAKTORY_HOST") do
      Faktory.Configuration.init()
      [{Faktory.Supervisor, []}]
    else
      []
    end
  end
end
