defmodule Sanbase.Application.Queries do
  import Sanbase.ApplicationUtils

  def init() do
    Sanbase.Nostrum.init()
    :ok
  end

  def children() do
    children = [
      # put :nostrum in included_applications and start the app manually here only if it has picked up
      # credentials from env var
      start_if(
        fn ->
          %{
            id: Nostrum.Application,
            start: {Nostrum.Application, :start, [:normal, []]}
          }
        end,
        fn -> Sanbase.Nostrum.enabled?() end
      ),
      start_if(
        fn -> Sanbase.DiscordConsumer end,
        fn -> Sanbase.Nostrum.enabled?() end
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
