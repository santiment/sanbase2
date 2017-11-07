defmodule Mix.Tasks.Influx.Setup do
  use Mix.Task

  @shortdoc "Setup the InfluxDB storage"

  alias Sanbase.Prices.Store

  def run(databases_to_create) do
    {:ok, _started} = Application.ensure_all_started(:sanbase)

    databases_to_create
    |> Enum.each(fn database ->
      database
      |> Instream.Admin.Database.create()
      |> Store.execute()
    end)
  end
end
