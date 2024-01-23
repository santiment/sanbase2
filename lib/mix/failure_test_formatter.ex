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
    config =
      case test do
        %ExUnit.Test{state: {:failed, [{:error, _error, failures}]}} = test
        when is_list(failures) ->
          # Add a leading dot so the file:line string can be copy-pasted in the
          # terminal to directly execute it
          file = String.replace_leading(test.tags.file, File.cwd!() <> "/", "")
          line = test.tags.line

          %{
            config
            | failed: ["#{file}:#{line}" | config.failed],
              failure_counter: config.failure_counter + 1
          }

        e ->
          IO.warn("Unexpected failed test format. Got: #{inspect(e)}")
          config
      end

    {:noreply, config}
  end

  def handle_cast({:suite_finished, _times_us}, config) do
    print_suite(config)
    {:noreply, config}
  end

  def handle_cast(_, config) do
    {:noreply, config}
  end

  defp print_suite(config) do
    if config.failure_counter > 0 do
      message = config.failed |> Enum.map(&(" " <> &1)) |> Enum.join("\n")

      formatted_message =
        IO.ANSI.red() <> "\n\nFailed tests:\n" <> message <> "\n" <> IO.ANSI.reset()

      IO.puts(formatted_message)
    end
  end
end
