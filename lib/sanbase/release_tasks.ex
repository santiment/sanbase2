defmodule Sanbase.ReleaseTasks do
  alias Sanbase.ReleaseTasks.Migrate
  alias Sanbase.ReleaseTasks.InfluxDB

  def run do
    # Load the code for myapp, but don't start it
    :ok = Application.load(:sanbase)

    Migrate.run
    InfluxDB.run

    # Signal shutdown
    IO.puts "Success!"
    :init.stop()
  end
end
