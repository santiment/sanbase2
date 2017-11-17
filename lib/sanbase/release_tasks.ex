defmodule Sanbase.ReleaseTasks do
  alias Sanbase.ReleaseTasks.Migrate

  def run do
    # Load the code for myapp, but don't start it
    :ok = Application.load(:sanbase)

    Migrate.run

    # Signal shutdown
    IO.puts "Success!"
    :init.stop()
  end
end
