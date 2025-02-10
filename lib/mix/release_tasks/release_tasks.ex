defmodule Sanbase.ReleaseTasks do
  @moduledoc false
  alias Sanbase.ReleaseTasks.Migrate

  def migrate do
    # Load the code for myapp, but don't start it
    Application.load(:sanbase)

    Migrate.run()

    # Alert shutdown
    IO.puts("Success!")
    :init.stop()
  end

  def run do
    # Load the code for myapp, but don't start it
    Application.load(:sanbase)

    Migrate.run()

    # Alert shutdown
    IO.puts("Success!")
    :init.stop()
  end
end
