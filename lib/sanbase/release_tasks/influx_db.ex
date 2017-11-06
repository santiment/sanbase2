defmodule Sanbase.ReleaseTasks.InfluxDB do
  alias Sanbase.Prices.Store

  @start_apps [
  ]

  def run do
    IO.puts "Starting dependencies.."
    # Start apps necessary for executing migrations
    Enum.each(@start_apps, &Application.ensure_all_started/1)

    Supervisor.start_link([Store.child_spec], [strategy: :one_for_one, name: Sanbase.ReleaseTasks.InfluxDB])

    Application.fetch_env!(:sanbase, Sanbase.ExternalServices.Coinmarketcap)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()
  end
end
