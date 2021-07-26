defmodule Sanbase.ReleaseTasks do
  alias Sanbase.ReleaseTasks.Migrate

  def run do
    # Load the code for myapp, but don't start it
    Application.load(:sanbase)

    Migrate.migrate()

    # Alert shutdown
    IO.puts("Success!")
    :init.stop()
  end
end
