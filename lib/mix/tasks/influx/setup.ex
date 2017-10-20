defmodule Mix.Tasks.Influx.Setup do
  use Mix.Task

  @shortdoc "Setup the InfluxDB storage"

  alias Sanbase.Prices.Store

  def run(_args) do
    {:ok, _started} = Application.ensure_all_started(:sanbase)

    Store.config[:database]
    |> Instream.Admin.Database.create()
    |> Store.execute()
  end
end
