defmodule Sanbase.FailedTestFormatter do
  @moduledoc false
  use GenServer

  ## Callbacks

  def init(_opts) do
    {:ok,
     %{
       failed: [],
       failure_counter: 0
     }}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _}} = test}, config) do
    %ExUnit.Test{
      state:
        {:failed,
         [
           {:error, _error,
            [
              {_module, _test_name, _, [file: file, line: line]}
            ]}
         ]}
    } = test

    config = %{
      config
      | failed: ["#{file}:#{line}" | config.failed],
        failure_counter: config.failure_counter + 1
    }

    {:noreply, config}
  end

  def handle_cast({:suite_finished, _run_us, _load_us}, config) do
    print_suite(config)
    {:noreply, config}
  end

  def handle_cast(_, config) do
    {:noreply, config}
  end

  defp print_suite(config) do
    if config.failure_counter > 0 do
      message = config.failed |> Enum.join("\n")
      IO.puts("Failed tests:\n" <> message)
    end
  end
end
