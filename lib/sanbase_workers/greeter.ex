defmodule SanbaseWorkers.Greeter do
  use Faktory.Job

  alias SanbaseWorkers.Greeter

  faktory_options queue: "greeter", retries: 5

  def perform(name) do
    IO.puts "Hello, #{name}"

    Process.sleep(1)
    Greeter.perform_async([name])
  end
end
